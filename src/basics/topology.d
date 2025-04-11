module basics.topology;

/* Topology represents a rectangle of a given size, possibly with one or both
 * sides wrapping around. Can compute distances.
 *
 * If size/topology is changed, protected overridables are called.
 *
 * Torbit (in module graphic.torbit) is the most important class inheriting
 * from Topology. Torbits are Allegro 5 bitmaps that support torus drawing.
 */

import std.algorithm;
import std.conv;
import std.math;
import std.range;

import basics.help; // positiveMod
public import basics.rect;

class Topology {
private:
    int  _xl, _yl; // x- and y-length of our rectangular area
    bool _tx, _ty; // torus property in either direction, making edges loop

public:
    this(this T)(int nxl, int nyl, bool ntx = false, bool nty = false
    ) pure nothrow @safe @nogc
    in {
        assert (nxl > 0 && nyl > 0, "Topology: (xl, yl) > 0 required.");
    }
    do {
        _xl = nxl;
        _yl = nyl;
        _tx = ntx;
        _ty = nty;
    }

    Topology clone() const { return new Topology(this); }

    this(this T)(in Topology rhs) pure nothrow @safe @nogc
    {
        assert (rhs);
        _xl = rhs._xl;
        _yl = rhs._yl;
        _tx = rhs._tx;
        _ty = rhs._ty;
    }

    final const nothrow pure @nogc @safe {
        int xl() { return _xl; }
        int yl() { return _yl; }
        bool torusX() { return _tx; }
        bool torusY() { return _ty; }

        bool matches(in Topology rhs)
        {
            return rhs && _xl == rhs._xl && _yl == rhs._yl
                       && _tx == rhs._tx && _ty == rhs._ty;
        }

        Point wrap(in Point p)
        {
            return Point(_tx ? positiveMod(p.x, _xl) : p.x,
                         _ty ? positiveMod(p.y, _yl) : p.y);
        }

        // If the point is off the non-torus, return what's closest to that.
        // If the point is off the torus, this is identical to this.wrap(p).
        Point clamp(in Point p)
        {
            return Point(_tx ? positiveMod(p.x, _xl) : .clamp(p.x, 0, xl - 1),
                         _ty ? positiveMod(p.y, _yl) : .clamp(p.y, 0, yl - 1));
        }

        // This computes distances similar to (1st_arg - 2nd_arg), but it
        // check for shortcuts around the cylinder/torus if appropriate.
        int distanceX(in int x1, in int x2)
        {
            if (! _tx) return x2 - x1;
            else {
                int[3] possible = [x2-x1, x2-x1-_xl, x2-x1+_xl];
                return std.algorithm.minPos!"abs(a) < abs(b)"(possible[])[0];
            }
        }

        int distanceY(in int y1, in int y2)
        {
            if (! _ty) return y2 - y1;
            else {
                int[3] possible = [y2-y1, y2-y1-_yl, y2-y1+_yl];
                return std.algorithm.minPos!"abs(a) < abs(b)"(possible[])[0];
            }
        }

        float hypot(in int x1, in int y1, in int x2, in int y2)
        {
            return std.math.sqrt(hypotSquared(x1, y1, x2, y2).to!float);
        }

        int hypotSquared(in int x1, in int y1, in int x2, in int y2)
        {
            immutable int dx = distanceX(x2, x1);
            immutable int dy = distanceY(y2, y1);
            return (dx * dx + dy * dy);
        }

        bool rectIntersectsRect(Rect a, Rect b)
        {
            return lineIntersectsLine(a.x, a.xl, b.x, b.xl, _xl, _tx)
                && lineIntersectsLine(a.y, a.yl, b.y, b.yl, _yl, _ty);
        }

        bool isPointInRectangle(in Point p, Rect rect)
        {
            return rectIntersectsRect(Rect(p.x, p.y, 1, 1), rect);
        }
    }

    final const {
        int torusAverageX(Range)(Range range) const if (isInputRange!Range)
        {
            return torusAverage(xl, torusX, (a, b) => distanceX(a, b), range);
        }

        int torusAverageY(Range)(Range range) const if (isInputRange!Range)
        {
            return torusAverage(yl, torusY, (a, b) => distanceY(a, b), range);
        }
    }

    final void resize(in int nxl, in int nyl)
    in {
        assert (_xl > 0, "Topology: xl > 0 required");
        assert (_yl > 0, "Topology: yl > 0 required");
    }
    do {
        if (_xl == nxl && _yl == nyl)
            return;
        _xl = nxl;
        _yl = nyl;
        onResize();
        onAnyChange();
    }

    final void setTorusXY(in bool x, in bool y)
    {
        if (_tx == x && _ty == y)
            return;
        _tx = x;
        _ty = y;
        onAnyChange();
    }

    version (assert) {
        override string toString() const
        {
            return "Top(" ~ _xl.to!string ~ ", " ~ _yl.to!string ~ ", "
                ~ _tx.to!string ~ ", " ~ _ty.to!string ~ ")";
        }
    }

protected:
    void onResize()    { }
    void onAnyChange() { }
}

private:

int torusAverage(Range)(
    in int  screenLen,
    in bool torus,
    in int delegate(int, int) dist,
    scope Range hatchPoints
) if (isInputRange!Range)
{
    immutable int len = hatchPoints.walkLength.to!int;
    if (len == 0)
        return screenLen / 2;
    immutable int avg = hatchPoints.sum / len;
    if (! torus)
        return avg;
    auto distToAllHatches(in int point)
    {
        return hatchPoints.map!(h => dist(point, h).abs).sum;
    }
    int closestPoint(in int a, in int b)
    {
        return distToAllHatches(a) <= distToAllHatches(b) ? a : b;
    }
    auto possiblePointsOnTorus = sequence!((unused, n) =>
        (avg + n.to!int * screenLen/len) % screenLen).takeExactly(len);
    static assert (is (typeof(possiblePointsOnTorus[0]) == int));
    return possiblePointsOnTorus.reduce!closestPoint;
}

bool lineIntersectsLine(
    int a, in int al, // first  line's start and length
    int b, in int bl, // second line's start and length
    in int len, in bool torus // underlying one-dimensional topology
) pure nothrow @safe @nogc
{
    bool intersects() {
        return ! (b >= a + al)  // not lying alongside like so: --a--  ---b---
            && ! (a >= b + bl); // not lying alongside like so: ---b---  --a--
    }
    if (! torus)
        return intersects;
    a = positiveMod(a, len);
    b = positiveMod(b, len);
    if (intersects)
        return true;
    a += len; // try with (line a) around the torus
    if (intersects)
        return true;
    a -= 2 * len; // try around the torus in the other direction
    return intersects;
}

unittest {
    // Our topology has a length of 100 in x-direction, 200 in y-direction,
    // and both wrappings. It's a torus.
    auto topol = new Topology(100, 200, true, true);
    bool rir(Rect a, Rect b) { return topol.rectIntersectsRect(a, b); }
    // Rectangles are specified as follows:
    // Rect(x of top-left corner,  y of top-left-corner,
    //      length in x-direction, length in y-direction).
    assert (  rir(Rect( 20, 30, 10, 15), Rect(  25,  40, 10, 15)));
    assert (! rir(Rect( 20, 30, 10, 15), Rect(  25, 340, 10, 15)));
    assert (  rir(Rect(120, 30, 10, 15), Rect(-175, 440, 10, 15)));
    assert (! rir(Rect( 90, 90, 20, 20), Rect(  10,  10, 20, 20)));
    assert (  rir(Rect( 90, 90, 21, 21), Rect(  10, 110, 10, 10)));
}
