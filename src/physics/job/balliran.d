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
    // constants during iteration
    Point _start;
    int _speedX;
    int _speedY;

    // iteration will change these
    Point _now;
    int _stepsTaken;

public:
    @disable this();
    this(Point start, int speedX, int speedY)
    in {
        assert (start.x % 2 == 0, "BallisticRange needs even x coordinates.");
        assert (speedX % 2 == 0, "BallisticRange needs even x speeds.");
    }
    do {
        _start = _now = start;
        _speedX = speedX;
        _speedY = speedY;
    }

    @property const pure {
        // ">", not "==": OK to call front when we're at the target position.
        // Then we get the final point of the flight for that step.
        bool  empty() { return _stepsTaken > stepsMax; }
        Point front() in { assert (! empty); } do { return _now; }
        int stepsTaken() { return _stepsTaken; }
        int stepsMax() { return _speedX.abs / 2 + _speedY.abs; }
    }

    auto save() inout pure { return this; }

    void popFront()
    in { assert (! empty); }
    do {
        ++_stepsTaken;
        if (empty)
            return;
        immutable candidateX = _now + Point(_speedX >= 0 ? 2 : -2, 0);
        immutable candidateY = _now + Point(0, _speedY >= 0 ? 1 : -1);
        immutable goal = _start + Point(_speedX, _speedY);
        _now =  triangleArea(_start, goal, candidateY)
             <= triangleArea(_start, goal, candidateX)
            ? candidateY : candidateX;
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
    // The example from the introduction comment. Let's choose A = (0, 0).
    assert (BallisticRange(Point(0, 0), 8, -2).equal([
        Point(0, 0),
        Point(2, 0),
        Point(2, -1),
        Point(4, -1),
        Point(6, -1),
        Point(6, -2),
        Point(8, -2),
    ]));

    // An example where we move the same distance horizontally and vertically,
    // to show how moving horizontally in steps of 2 affects the trajectory.
    assert (BallisticRange(Point(10, 10), 6, 6).equal([
        Point(10, 10),
        Point(10, 11),
        Point(12, 11),
        Point(12, 12),
        Point(12, 13),
        Point(14, 13),
        Point(14, 14),
        Point(14, 15),
        Point(16, 15),
        Point(16, 16),
    ]));

    // In a very steep fall that moves horizontally only once,
    // we should move horizontally in the middle of the fall.
    auto ran = BallisticRange(Point(0, 0), 2, 10);
    assert (ran.walkLength == 12);
    assert (ran.count!(p => p.x == 0) == 6);
    assert (ran.count!(p => p.x == 2) == 6);

    assert (BallisticRange(Point(0, 0), 8, 0).walkLength == 5);
    assert (BallisticRange(Point(0, 0), 0, 8).walkLength == 9);
}
