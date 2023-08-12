module physics.job.ballifly;

import std.algorithm;
import std.format;
import std.math; // abs
import std.range;

import physics.job;

abstract class BallisticFlyer : Job {
public:
    int speedX; // should be >= 0. Is really speed ahead, not absolute x dir.
    int speedY;
    int pixelsFallen; // always >= 0. Upflinginging keeps 0. Resets on fling.

    enum speedYToFloat = 15;
    enum pixelsSafeToFall = Faller.pixelsSafeToFall;

    protected void copyFrom(in BallisticFlyer rhs)
    {
        assert (rhs, "can't copy from null job");
        speedX = rhs.speedX;
        speedY = rhs.speedY;
        pixelsFallen = rhs.pixelsFallen;
    }

    override void perform()
    {
        assert (speedX >= 0, "Lix should only fly forwards. Turn first.");
        assert (speedX % 2 == 0, "Lix need even speed. Fix fling-assigner.");

        immutable target = planMovement();
        if (moveToAndReact(target) == Collision.pathBlockedAndBecomeCalled)
            return;

        speedY += accel(speedY);
        selectFrame();
        if (speedY >= speedYToFloat) {
            if (lixxie.abilityToFloat) lixxie.become(Ac.floater);
            else if (ac != Ac.tumbler) lixxie.become(Ac.tumbler);
        }
    }

protected:
    enum Collision {
        pathClear,
        pathBlocked,
        pathBlockedAndBecomeCalled,
    }

    enum int biggestLargeAccelSpeedY = 12;
    static int accel(int ysp) pure
    {
        return (ysp <= biggestLargeAccelSpeedY) ? 2 : (ysp < 32) ? 1 : 0;
    }

    // bool collideWithUpperBody() const { return false; } // dtodo
    bool splatUpsideDown() const { return false; }
    bool collideAfterMoving() const { return true; } // floater should not

    abstract Collision reactToWall();
    abstract Collision onLandingWithoutSplatting();
    abstract void selectFrame();

    // Step (1) relies on this virtual method.
    // E.g. the Jumper can latch onto terrain high up, that should definitely
    // report a collision in override wouldCollideAt. Default only at foot.
    bool wouldCollideAt(in Point ifFootWereAt) const
    out (ret) {
        if (ret == false)
            // Cannot collide with less than our base class collides with
            assert (! lixxie.env.getSolidEven(ifFootWereAt + Point(0, 1)));
    }
    do {
        // In the base class BallisticFlyer here, the return must be
        // the exact negative of the assert in the out contract.
        // Don't call lixxie.isSolid: We ask ifFootWereAt, not where foot is.
        return lixxie.env.getSolidEven(ifFootWereAt + Point(0, 1));
    }

private:
    struct PlannedMovement {
        Point footGoal;
        bool collideAtGoal = false;
        BallisticRange.Step lastGood = BallisticRange.Step.down;
        BallisticRange.Step nextBad = BallisticRange.Step.down;
    }

    BallisticRange rangeBySpeed() const
    {
        return BallisticRange(speedX, speedY);
    }

    // Step (1) in geoo's proposal: Plan trajectory
    PlannedMovement planMovement() const
    {
        if (wouldCollideAt(lixxie.foot)) {
            return PlannedMovement(lixxie.foot, true);
        }
        PlannedMovement ret;
        ret.footGoal = lixxie.foot;
        BallisticRange ran = rangeBySpeed();
        while (! ran.empty && ! wouldCollideAt(ran.front)) {
            lastGood = ran.front;
            ran.popFront;
        }
        return lastGood;
    }

    // Step (2) in geoo's proposal: Determine type of collision by surrounding
    bool foundFloor() const { return lixxie.isSolid(0, 2); }

    bool foundWall() const
    {
        return wouldCollideAt(lixxie.foot + Point(2*lixxie.dir, 0));
    }

    bool foundCeiling() const
    {
        return speedY < 0
            && wouldCollideAt(lixxie.foot + Point(0, -1));
    }

    // Step (3) of geoo's proposal: Execute the movement found by step (1)
    // and react to the results of step (2).
    Collision moveToAndReact(in Point target)
    {
        // Move along the trajectory. Very good: Point target is not yet
        // wrapped around a torus. Move by single pixels to track encounters.
        pixelsFallen = speedY < 0 ? 0 : pixelsFallen - lixxie.ey + target.y;
        foreach (ref const point; rangeBySpeed) {
            lixxie.ex = point.x;
            lixxie.ey = point.y;
            if (point == target)
                break;
        }
        // Step (2) is determine surroundings, step (3) is react to them:
        return foundFloor   ? reactToFloor()
            :  foundCeiling ? reactToCeiling()
            :  foundWall    ? reactToWall()
            : Collision.pathClear;
    }

    Collision reactToFloor()
    {
        assert (lixxie.isSolid, "see foundFloor() for why this should be");
        if (pixelsFallen > pixelsSafeToFall && ! lixxie.abilityToFloat) {
            immutable sud = this.splatUpsideDown();
            lixxie.become(Ac.splatter);
            if (sud)
                lixxie.job.frame = 10;
            return Collision.pathBlockedAndBecomeCalled;
        }
        else {
            return onLandingWithoutSplatting();
        }
    }

    Collision reactToCeiling()
    {
        auto ret = Collision.pathBlocked;
        immutable newSpeedX = speedX / 2;
        if (ac != Ac.tumbler) {
            lixxie.become(Ac.tumbler);
            ret = Collision.pathBlockedAndBecomeCalled;
        }
        // In weird cases, we might be stunner now because we're completely
        // immobilized. That's fine.
        if (ac == Ac.tumbler) {
            auto tumbling = cast (BallisticFlyer) lixxie.job;
            assert (tumbling);
            // We set speedY, but, depending on whether we were a tumbler
            // before we hit the ceiling, we'll return different BecomeCalled.
            // BallisticFlyer.perform() will increase speedY if we return
            // BecomeCalled.no. This means that tumblers bumping ceilings will
            // fall faster afterwards than jumpers bumping ceilings. I'm unsure
            // whether this difference is good, but I'll keep it for now.
            tumbling.speedY = 4;
            tumbling.speedX = newSpeedX + (newSpeedX & 1);
        }
        return ret;
    }
}
