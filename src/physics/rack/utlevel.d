module physics.rack.utlevel;

version (assert):

import basics.help;
import basics.rect;
import tile.phymap;

import std.conv;
import std.exception;
import std.utf : count;

class UtLevel {
private:
    string[] _land;

public:
    bool torusX;
    bool torusY;

public:
    this(string[] aLand)
    in {
        assert (aLand.length >= 1, "Can't make a (0 x 0)-sized level.");
        foreach (i, line; aLand) {
            enforce(line.count == aLand[0].count, text(
                "Line ", i, ` "`, line,
                `" of the land: Bad number of UTF code points.`,
                " It has ", line.count,
                ", but we expected ", aLand[0].count,
                ` as in line 0, "`, aLand[0], `".`));
        }
    }
    do {
        _land = aLand;
    }

    int xl() const pure nothrow @safe @nogc { return 2 * _land[0].len; }
    int yl() const pure nothrow @safe @nogc { return 2 * _land.len; }

    Point[] lixxieStartingPoints() const pure @safe
    {
        Point[] ret = [];
        forEach2x2((in Point where, in dchar source) {
            addPointIfAsciiNumber(ret, where, source);
        });
        return ret;
    }

    Phymap toPhymap() const pure @safe
    {
        auto ret = new Phymap(xl, yl, torusX, torusY);
        forEach2x2((in Point where, in dchar source) {
            add2x1EarthIfItIs(ret, where, source, '▀');
            add2x1EarthIfItIs(ret, where + Point(0, 1), source, '▄');
        });
        return ret;
    }

private:
    const pure @safe void forEach2x2(
        void delegate(in Point, in dchar) pure @safe func
    ) {
        for (int line = 0; line < _land.len; ++line) {
            int x = 0;
            foreach (dchar dcharFromLine; _land[line]) {
                func(Point(x, 2 * line), dcharFromLine);
                x += 2;
            }
        }
    }

    static pure @safe void addPointIfAsciiNumber(
        ref Point[] ret, in Point where, in dchar source
    ) {
        if (source < '0' || source > '9') {
            return;
        }
        const size_t id = source - '0';
        if (ret.length < id + 1) {
            ret.length = id + 1;
        }
        enforce(ret[id] == Point.init,
            text("Duplicate lix ID in the level.",
                " ID: ", id,
                " First instance: ", ret[id],
                " Second instance: ", where));
        ret[id] = where;
    }

    static nothrow pure @safe void add2x1EarthIfItIs(
        Phymap target, in Point where, in dchar source, in dchar halfSolid
    ) {
        enum phybitAir = 0;
        const Phybitset topHalf = source == '█' || source == halfSolid
            ? Phybit.terrain : phybitAir;
        target.add(where, topHalf);
        target.add(where + Point(1, 0), topHalf);
    }
}

// 2x2 full air:   .
// 2x2 full earth: █
// 2x1 upper half: ▀
// 2x1 lower half: ▄
// 2x2 Steel:      ▒

unittest {
    auto utlev = new UtLevel([
        ".....0..",
        "....██▀▄",
        ]);
    assert (utlev.lixxieStartingPoints.length == 1);
    assert (utlev.lixxieStartingPoints[0] == Point(10, 0));

    auto phymap = utlev.toPhymap;
    assert (phymap.xl == utlev.xl);
    assert (phymap.yl == utlev.yl);
}
