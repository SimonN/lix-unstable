module physics.job.balliran;

/* In the following diagrams, the dots are spaced 2 units apart horizontally
 * and 1 unit apart vertically, matching Lix's rule that all lixes' x coords
 * must be even, but y coordinates can be any integer.
 *
 * . . . . . . . You're at A, and want to move to B in one frame. You give
 * . . . . --B . to BallisticRange this data:
 * . . .---. . . First arg is A, and
 * . A-- . . . . second arg is speed's x and y to get from A to B in one frame.
 * . . . . . . . The speed in this example is (+8, -2) == (8 right, 2 up).
 *
 * We compute the number of steps by the following metric: Moving horizontally
 * by (2 units = 1 dot) costs 1, and moving vertically by (1 unit = 1 dot)
 * also costs 1.
 *
 * . . . . . . . BallisticRange computes that you need 6 steps to get there in
 * . . . . 5 6 . our special metric. front() is A. The image on the left shows
 * . . 2 3 4 . . what front() will be after you've popFront()ed n times.
 * . 0 1 . . . . When you're at B and popFront again, the range will be empty.
 * . . . . . . . This means that the target B is part of the range.
 */

import std.algorithm;
import std.range;
import std.math;

public import basics.rect;

static assert (isForwardRange!BallisticRange);

struct BallisticRange {
@nogc:
private:
    Point _goal;
    Point _now = Point(0, 0);

public:
    enum Step { down, up, ahead, }

    @disable this();
    this(int speedX, int speedY)
    in {
        assert (speedX % 2 == 0, "BallisticRange needs even x speeds.");
        assert (speedX >= 0, "BallisticRange goes forward (>= 0) only.");
    }
    do {
        _goal = Point(speedX, speedY);
    }

    bool empty() const { return _now == _goal; }

    Step front()
    in { assert (! empty); }
    do {
        immutable candidateX = _now + Point(2, 0);
        immutable candidateY = _now + Point(0, _goal.y >= 0 ? 1 : -1);
        if (triangleArea(_now, _goal, candidateY)
          > triangleArea(_now, _goal, candidateX)
        ) {
            return Step.ahead;
        }
        return _goal.y >= 0 ? Step.down : Step.up;
    }

    auto save() inout nothrow pure @safe @nogc { return this; }

    void popFront()
    in { assert (! empty); }
    do {
        final switch (front()) {
            case Step.down: _now += Point(0, 1); return;
            case Step.up: _now += Point(0, -1); return;
            case Step.ahead: _now += Point(2, 0); return;
        }
    }
}

// Normally, we'd use a Topology to compute distances.
// But we don't need that for the small-scale sub-frame movement
// because the candidates are so close togethe at distance (1, 1).
// Even when one candidate would wrap around on a torus
// and the other would not, the following distance comparison gives
// the same results either on a torus or by normal Pythagoras.
// If both candidates are the same distance away, move vertically.
private int triangleArea(in Point a, in Point b, in Point c) pure @nogc
{
    return abs((b.x - a.x) * (c.y - a.y)
             - (c.x - a.x) * (b.y - a.y));
}

unittest {
with (BallisticRange.Step) {
    // The example from the introduction comment. Let's choose A = (0, 0).
    assert (BallisticRange(8, -2).equal([
        ahead, up, ahead, ahead, up, ahead,
    ]));

    // An example where we move the same distance horizontally and vertically,
    // to show how moving horizontally in steps of 2 affects the trajectory.
    assert (BallisticRange(6, 6).equal([
        up, ahead, up,
        up, ahead, up,
        up, ahead, up,
    ]));

    // In a very steep fall that moves horizontally only once,
    // we should move horizontally in the middle of the fall.
    assert (BallisticRange(2, 10).equal([
        down, down, down, down, down, ahead,
        down, down, down, down, down,
    ]));


    assert (BallisticRange(8, 0).walkLength == 4);
    assert (BallisticRange(0, 8).walkLength == 8);
}}
