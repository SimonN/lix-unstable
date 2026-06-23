module net.name;

/*
 * A Name is the necessary information to identify a lix in a match.
 * (Name doesn't mean player's name.)
 *
 * Array slot and tribe style (owner style) is enough information to retrieve
 * a lix. Lixes are value types and can't be identified by equality.
 * A lix is usually, but not always, drawn in her tribe's style. E.g.,
 * on hovering over a lix, you'll see the highlighting style for owner red.
 */

import net.style;

struct Name {
pure nothrow @safe @nogc:
    uint rawBytes;

    this(in Style anOwner, in int anId)
    {
        rawBytes = ((anOwner & 0xFF) << 24) + anId;
    }

const:
    Style owner()
    {
        static assert (Style.min >= 0);
        static assert (Style.max <= 255);
        return cast (Style) (rawBytes >> 24);
    }

    int id()
    {
        return rawBytes & 0xFF_FFFF;
    }

    int opCmp(ref const Name rhs)
    {
        return (rawBytes > rhs.rawBytes) - (rawBytes < rhs.rawBytes);
    }
}

unittest {
    const Name a;
    const Name b = Name(Style.red, 23);
    assert (a.id + 23 == b.id);
    assert (a.id + 24 != b.id);
    assert (a != b);
    assert (a < b);
}
