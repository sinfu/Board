module nyo.detail.io.scanner;


/*
 * Stateful functor recogninzing one UTF-8 code unit immediately past
 * a newline code.  It returns true if and only if an input byte is
 * at the beginning of a new line.
 *
 * This object is bit-copyable preserving the internal state.
 *
 * New-line codes in UTF-8:
 *  -   LF = 0A
 *  -   FF = 0C
 *  -   CR = 0D
 *  - CRLF = 0D 0A
 *  -  NEL = C2 85
 *  -   LS = E2 80 A8
 *  -   PS = E2 80 A9
 *
 * Standards:
 *  - Unicode 4.0-5.2, 5.8 Newline Guidelines / Rec. R4
 *  - Superseded TR: http://www.unicode.org/reports/tr13/
 */
struct PastNewLine
{
 pure nothrow @safe:
    // The internal implementation is a finite state machine.

    bool opCall(char u)
    {
        immutable input = toChar[u];
        immutable  next = transit[state_][input];

        if (next == State.accept)
        {
            // epsilon transition
            state_ = transit[State.init][input];
            return true;
        }
        else
        {
            state_ = next;
            return false;
        }
    }


 private:

    State state_;

    invariant()
    {
        // There's an epsilon transition from accept to init.
        assert(state_ != State.accept);
    }


 private static:

    enum State : ubyte
    {
        init,
        pastCR,     // ready for CR or CRLF
        pastC2,     // ready for NEL
        pastE2,
        pastE280,   // ready for LS or PS
        ready,
        accept
    }

    // Choose significant UTF-8 code units to reduce the size of our
    // state transition table.
    enum Char : ubyte
    {
        other,
        LF, FF, CR,
        x80, x85, xA8, xA9, xC2, xE2,
    }

    immutable Char[char.max + 1] toChar =
        [ '\n'  : Char. LF, '\f'  : Char. FF, '\r'  : Char. CR,
          '\xC2': Char.xC2, '\x85': Char.x85, '\xE2': Char.xE2,
          '\x80': Char.x80, '\xA8': Char.xA8, '\xA9': Char.xA9, ];

    // State transition table
    //
    // - The array dimension being State.max isn't a bug.  The row for
    //   State.accept (== State.max) is omitted because this DFA has an
    //   epsilon transition from State.accept to State.init, which is
    //   handled in the opCall above.
    //
    // - The compiler automatically assigns State.init to unfilled cells.
    //   This is good; we will fall back to State.init on encountering
    //   any non-newline code and then continue the job.
    //
    immutable State[ Char.max + 1]
                   [State.max    ] transit =
        [ State.init:     [ Char.   LF: State.   ready,    // LF
                            Char.   FF: State.   ready,    // FF
                            Char.   CR: State.  pastCR,
                            Char.  xC2: State.  pastC2,
                            Char.  xE2: State.  pastE2 ],
          State.pastCR:   [ Char.   LF: State.   ready,    // CRLF
                            Char.   FF: State.  accept,
                            Char.   CR: State.  accept,
                            Char.  x80: State.  accept,
                            Char.  x85: State.  accept,
                            Char.  xA8: State.  accept,
                            Char.  xA9: State.  accept,
                            Char.  xC2: State.  accept,
                            Char.  xE2: State.  accept,
                            Char.other: State.  accept ],
          State.pastC2:   [ Char.  x85: State.   ready ],  // NEL = C2 85
          State.pastE2:   [ Char.  x80: State.pastE280 ],
          State.pastE280: [ Char.  xA8: State.   ready,    // LS = E2 80 A8
                            Char.  xA9: State.   ready ],  // PS = E2 80 A9
          State.ready:    [ Char.   LF: State.  accept,
                            Char.   FF: State.  accept,
                            Char.   CR: State.  accept,
                            Char.  x80: State.  accept,
                            Char.  x85: State.  accept,
                            Char.  xA8: State.  accept,
                            Char.  xA9: State.  accept,
                            Char.  xC2: State.  accept,
                            Char.  xE2: State.  accept,
                            Char.other: State.  accept ]
        ];
}

unittest
{
    static struct R
    {
        char input;
        bool response;
    }
    enum t = true, f = false;

    immutable story =
    [
        R( 'a', f), R(   'b', f), R(   'c', f), R(  '\n', f),
        R('\r', t),
        R( '1', t), R(   '2', f), R(   '3', f), R(  '\r', f),
        R('\r', t),
        R( 'x', t), R(  '\r', f), R(  '\n', f),
        R( 'p', t), R('\xC2', f), R('\x85', f),
        R( 'q', t), R('\xE2', f), R('\x80', f), R('\xA8', f),
        R( 'r', t), R('\xE2', f), R('\x80', f), R('\xA9', f),
        R('\0', t)
    ];
    PastNewLine fun;
    foreach (s; story)
    {
        assert(fun(s.input) == s.response);
    }
}

