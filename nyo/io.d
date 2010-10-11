module nyo.io;


version = io_demo;

version (io_demo)
{
    import std.stdio;

    void main()
    {
        auto ast = Stream!DirectArray("abcdef\ruvwxyz\r\n012345\n\ropqrst");

        foreach (s; ast.byLine)
        {
            foreach (char u; s)
                writef("%02x ", u);
            writeln();
        }
    }
}



//----------------------------------------------------------------------------//


import std.range;
import std.string;

private
{
    template namespace_stdc()
    {
        import core.stdc.errno;
        import core.stdc.stdio;
    }
    mixin namespace_stdc stdc;

    template namespace_sys()
    {
        version (Windows)
        {
            import core.sys.windows.windows;
        }
        else version (Posix)
        {
            import core.sys.posix.fcntl;
            import core.sys.posix.unistd;
            import core.sys.posix.sys.stat;

            alias stat_t struct_stat;
        }
    }
    mixin namespace_sys sys;
}

import        nyo.algorithm;
import meta = nyo.meta;

import nyo.detail.io.scanner;


//----------------------------------------------------------------------------//


alias long streampos_t;

enum StreamDir
{
    input   = 0b0001,
    output  = 0b0010,
    both    = input | output,
}

enum SeekFrom
{
    begin,
    current,
    end
}



interface IODeviceTag {}
interface IOBufferTag {}


template isIODevice(D)
{
    enum isIODevice = is(D.Category : IODeviceTag);
}

template isIOBuffer(D)
{
    enum isIOBuffer = is(D.Category : IOBufferTag);
}


template isDirectAccessDevice(D)
{
    enum isDirectAccessDevice =
            __traits(compiles,
                {
                    D dev;
                    const(ubyte)[] data = dev.data;
                    dev.close();
                });
}


//----------------------------------------------------------------------------//
// File Device
//----------------------------------------------------------------------------//

struct FileDevice // POSIX
{
    interface Category : IODeviceTag {}

    alias File OptimalBuffer;


    @trusted this(in char[] path)
    {
        handle_ = sys.open(path.toStringz(), O_RDWR);
        if (handle_ == -1)
        {
            switch (errno)
            {
              default:
                throw new Exception("open");
            }
            assert(0);
        }
    }

    @trusted void close()
    {
        while (sys.close(handle_) == -1)
        {
            switch (errno)
            {
              case EINTR:
                continue;

              default:
                throw new Exception("close");
            }
            assert(0);
        }
        handle_ = -1;
    }

    @trusted ubyte[] read(ubyte[] store)
    {
        ssize_t r;

        while ((r = sys.read(handle_, store.ptr, store.length)) < 0)
        {
            switch (errno)
            {
              case EINTR:
                continue;

              case EAGAIN:
                return null;

              default:
                throw new Exception("read");
            }
            assert(0);
        }
        assert(r >= 0);
        return store[0 .. r];
    }

    @trusted inout(ubyte[]) write(inout(ubyte[]) data)
    {
        ssize_t r;
        while ((r = sys.write(handle_, data.ptr, data.length)) < 0)
        {
            switch (errno)
            {
              case EINTR:
                continue;

              case EAGAIN:
                return null;

              default:
                throw new Exception("write");
            }
            assert(0);
        }
        assert(r >= 0);
        return data[0 .. r];
    }

    @trusted streampos_t seek(streampos_t off, SeekFrom from)
    {
        off_t r;

        while ((r = sys.lseek(off, SEEK_SET)) < 0)
        {
            switch (errno)
            {
              default:
                throw new Exception("lseek");
            }
            assert(0);
        }
        assert(r >= 0);
        return r;
    }

    @trusted @property streampos_t size()
    {
        return stat.st_size;
    }

    @trusted @property struct_stat stat()
    {
        struct_stat stat = void;

        if (sys.fstat(handle_, &stat) < 0)
        {
            switch (errno)
            {
              case EBADF, EFAULT:
                assert(0);

              default:
                throw new Exception("fstat");
            }
            assert(0);
        }
        return stat;
    }

 private:
    int handle_;
}


//
// Optimal Buffer for FileDevice
//
struct File // TODO
{
    @trusted this(in char[] path)
    {
        handle_ = sys.open(path.toStringz(), O_RDONLY);
        buffer_ = BasicBuffer();
    }

    @trusted void close()
    {
        sys.close(handle_);
    }


    @property ubyte[] input() pure nothrow
    {
        return buffer_;
    }

    void consume(size_t n) pure nothrow
    {
    }

    @trusted bool refill()
    {
    }


    @trusted const(ubyte)[] write(const(ubyte)[] data)
    {
    }

    @trusted void flush()
    {
    }


    @trusted streampos_t seek(streampos_t off, SeekFrom from)
    {
        sys.lseek(off, SEEK_SET);
    }

    @trusted @property streampos_t size()
    {
        return stat().st_size;
    }


 private:

    @trusted struct_stat stat()
    {
        struct_stat stat = void;

        if (sys.fstat(handle_, &stat) < 0)
        {
        }
        return stat;
    }


 private:
    int     handle_;
    ubyte[] buffer_;
    size_t  current_;
    size_t  bottom_;
}



//----------------------------------------------------------------------------//
// Direct Array Device
//----------------------------------------------------------------------------//


struct DirectArray
{
    interface Category : IODeviceTag {}

 pure @safe:

    this(E)(E[] store) nothrow
    {
        data_ = cast(ubyte[]) store;
    }

    this()(size_t size)
    {
        data_ = new ubyte[](size);
    }


    void close() nothrow
    {
        data_ = null;
    }

    @property const(ubyte)[] data() const nothrow
    {
        return data_;
    }

    @property ubyte[] data() nothrow
    {
        return data_;
    }

 private:
    ubyte[] data_;
}



//----------------------------------------------------------------------------//
// General Buffer
//----------------------------------------------------------------------------//


struct StreamBuffer(Direct)
    if (isDirectAccessDevice!Direct)
{
    interface Category : IOBufferTag {}

 @safe:

    this()(Direct direct)
    {
        direct_ = direct;
    }

    this(Args...)(Args args)
    {
        direct_ = Direct(args);
    }


    //----------------------------------------------------------------//

    void close()
    {
        direct_.close();
    }

    streampos_t seek(streampos_t off,
                     SeekFrom    whence = SeekFrom.begin,
                     StreamDir   dir    = StreamDir.both)
    {
        foreach (on; meta.Sequence!("input", "output"))
        {
            mixin("alias           "~ on ~"     sequence;");
            mixin("alias           "~ on ~"Cur_ cursor_;");
            mixin("alias StreamDir."~ on ~"     direction;");

            if (!(dir & direction))
                continue;

            final switch (whence)
            {
              case SeekFrom.begin:
                cursor_ = cast(size_t) off;
                break;

              case SeekFrom.current:
                cursor_ += cast(size_t) off;
                break;

              case SeekFrom.end:
                cursor_ = sequence.length + cast(size_t) off;
                break;
            }
        }
        return 0;   // FIXME
    }


    //----------------------------------------------------------------//
    // Input end
    //----------------------------------------------------------------//

    @property streampos_t showmanyc() const pure nothrow
    {
        return input.length;
    }

    @property const(ubyte)[] input() const pure nothrow
    {
        return direct_.data[inputCur_ .. $];
    }

    void consume(size_t n) pure
    {
        if (n > input.length)
        {
            throw new Exception("input underflow");
        }
        inputCur_ += n;
    }

    bool refill() pure nothrow
    {
        return false;
    }


    //----------------------------------------------------------------//
    // Output end
    //----------------------------------------------------------------//

    @property ubyte[] output() pure nothrow
    {
        return direct_.data[outputCur_ .. $];
    }

    void commit(size_t n) pure
    {
        if (n > output.length)
        {
            throw new Exception("output overflow");
        }
        outputCur_ += n;
    }

    bool flush() pure nothrow
    {
        return false; // ?
    }

    inout(ubyte[]) write(inout(ubyte[]) data)
    {
        if (data.length > output.length)
        {
            throw new Exception("output overflow");
        }
        output[0 .. data.length] = data[];
        outputCur_ += data.length;
        return data;
    }


    //----------------------------------------------------------------//
 private:
    Direct direct_;
    size_t inputCur_;
    size_t outputCur_;
}



//----------------------------------------------------------------------------//
// Stream
//----------------------------------------------------------------------------//


// shorthand
template Stream(Device)
    if (isIODevice!Device)
{
    alias Stream!(StreamBuffer!Device) Stream;
}


struct Stream(Buffer)
    if (isIOBuffer!Buffer)
{
    // pass-in
    this()(Buffer buffer)
    {
        buffer_ = buffer;
    }

    // emplace
    this(Args...)(Args args)
    {
        buffer_ = Buffer(args);
    }

    void close()
    {
        buffer_.close();
    }



    //----------------------------------------------------------------//
    // Streaming Input
    //----------------------------------------------------------------//

    bool end()
    {
        return buffer_.input.empty && !buffer_.refill();
    }

    @trusted string readln()
    {
        PastNewLine pred;
        string    result;

        while (true)
        {
            auto input = buffer_.input;

            if (input.empty)
            {
                if (buffer_.refill())
                    continue;
                else
                    break;
            }
            assert(!input.empty);

            auto sep = bisect!pred(input);

            result ~= sep.before;
            buffer_.consume(sep.before.length);

            // BUG(?) @ buffer boundary
            if (!sep.after.empty)
                break;
        }
        return result;
    }


    // Formatted read
    @trusted T read(T)()
    {
    }

    @trusted Tuple!Rec read(Rec...)(dchar delim = dchar.init)
    {
    }


    //----------------------------------------------------------------//
    // Input Ranges
    //----------------------------------------------------------------//


    @property ByLine byLine()
    {
        return ByLine(this);
    }

    struct ByLine
    {
     @safe:

        this(Stream stream)
        {
            impl_ = new Impl;
            impl_.stream = stream;
            impl_.want   = true;
        }

        @property bool empty()
        {
            if (impl_.want)
                fetchNext();
            return impl_.empty;
        }

        @property const(char)[] front()
        {
            if (impl_.want)
                fetchNext();
            return impl_.front;
        }

        void popFront()
        {
            if (impl_.want)
                fetchNext();
            impl_.want = true;
        }


     private:

        void fetchNext()
        {
            impl_.want = false;

            if (auto line = impl_.stream.readln())
            {
                impl_.front = line;
            }
            else
            {
                impl_.empty = true;
            }
        }

        struct Impl
        {
            Stream stream;
            string front;
            bool   empty;
            bool   want;
        }
        Impl* impl_;
    }


    // istream_iterator<T>
    @property By!T by(T)()
    {
    }


    //----------------------------------------------------------------//
 private:
    Buffer buffer_;
}


