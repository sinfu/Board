module nyo.algorithm;

import std.functional;
import std.range;
import std.typecons;


/**
Bisects a forward range $(D r) at the first element satisfying a
unary predicate $(D pred).

Returns:
 2-tuple $(D (before, after)), where $(D before) is a subrange of $(D r)
 before the bisecting point (non-inclusive) and $(D after) is the rest.
 $(D after) is empty if no element in $(D r) satisfies the predicate.

Example:
--------------------
--------------------
 */
Tuple!(Take!R, "before", R, "after") bisect(alias pred, R)(R r)
    if (isForwardRange!R)
{
    auto p = r.save;
    auto q = r.save;
    size_t n;

    for (; !q.empty; q.popFront())
    {
        if (unaryFun!pred(q.front))
            break;
        ++n;
    }
    return typeof(return)(take(p, n), q);
}

unittest
{
    int[] r = [1,2,3,4,5];

    auto mid = bisect!"a == 3"(r);
    assert(mid.before == [1,2]);
    assert(mid.after == [3,4,5]);

    auto beg = bisect!"a == 1"(r);
    assert(beg.before == []);
    assert(beg.after == [1,2,3,4,5]);

    auto end = bisect!"a == 5"(r);
    assert(end.before == [1,2,3,4]);
    assert(end.after == [5]);

    auto none = bisect!"a == 0"(r);
    assert(none.before == [1,2,3,4,5]);
    assert(none.after == []);

    // degenerate
    int[] e;
    assert(bisect!"true"(e).before.empty);
    assert(bisect!"true"(e).after.empty);
    assert(bisect!"false"(e).before.empty);
    assert(bisect!"false"(e).after.empty);

    // typeof
    auto bis = bisect!"a == 2"(retro([1,2,3]));
    static assert(is(typeof(bis[0]) == Take!(Retro!(int[]))));
    static assert(is(typeof(bis[1]) ==       Retro!(int[]) ));

    // bad predicate
    void badpred(int e) {}
    static assert(!__traits(compiles, bisect!badpred([1,2,3])));
}


/**
Bisects a forward range $(D r) at the first element $(D x) that satisfies
a binary predicate $(D pred(x, e)).

Returns:
 2-tuple $(D (before, after)), where $(D before) is a subrange of $(D r)
 before the bisecting point (non-inclusive) and $(D after) is the rest.
 $(D after) is empty if no element in $(D r) satisfies the predicate.
 */
Tuple!(Take!R, "before", R, "after")
        bisect(alias pred = "a == b", R, E)(R r, E e)
    if (isForwardRange!R)
{
    auto p = r.save;
    auto q = r.save;
    size_t n;

    for (; !q.empty; q.popFront())
    {
        if (binaryFun!pred(q.front, e))
            break;
        ++n;
    }
    return typeof(return)(take(p, n), q);
}

unittest
{
    int[] r = [1,2,3,4,5];

    auto mid = bisect(r, 3);
    assert(mid.before == [1,2]);
    assert(mid.after == [3,4,5]);

    auto beg = bisect(r, 1);
    assert(beg.before == []);
    assert(beg.after == [1,2,3,4,5]);

    auto end = bisect(r, 5);
    assert(end.before == [1,2,3,4]);
    assert(end.after == [5]);

    auto none = bisect(r, 0);
    assert(none.before == [1,2,3,4,5]);
    assert(none.after == []);

    // degenerate
    int[] e;
    assert(bisect!"true"(e, 0).before.empty);
    assert(bisect!"true"(e, 0).after.empty);
    assert(bisect!"false"(e, 0).before.empty);
    assert(bisect!"false"(e, 0).after.empty);

    // typeof
    auto bis = bisect(retro([1,2,3]), 2);
    static assert(is(typeof(bis[0]) == Take!(Retro!(int[]))));
    static assert(is(typeof(bis[1]) ==       Retro!(int[]) ));

    // bad predicate
    void badpred(int a, int b) {}
    static assert(!__traits(compiles, bisect!badpred([1,2,3], 2)));
}

