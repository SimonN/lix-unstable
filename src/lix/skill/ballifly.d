module lix.skill.ballifly;

import std.algorithm;
import std.format;
import std.math; // abs
import std.range;

import lix;

abstract class BallisticFlyer : Job {

    int speedX; // should be >= 0. Is really speed ahead, not absolute x dir.
    int speedY;
    int pixelsFallen; // always >= 0. Upflinginging keeps 0. Resets on fling.

    mixin JobChild;

    enum speedYToFloat = 15;
    enum pixelsSafeToFall = {
       import lix.skill.faller; return Faller.pixelsSafeToFall;
    }();

    protected void copyFrom(in BallisticFlyer rhs)
    {
        assert (rhs, "can't copy from null job");
        speedX = rhs.speedX;
        speedY = rhs.speedY;
        pixelsFallen = rhs.pixelsFallen;
    }

    final override void perform()
    {
        assert (speedX >= 0, "Lix should only fly forwards. Turn first.");
        if (speedX % 2 != 0)
            ++speedX;
        if (moveSeveralTimes() == Collision.pathBlockedAndBecomeCalled) {
            return;
        }
        speedY += accel(speedY);
        selectFrame();
        if (speedY >= speedYToFloat) {
            if      (abilityToFloat)   become(Ac.floater);
            else if (ac != Ac.tumbler) become(Ac.tumbler);
        }
    }

protected:
    enum Collision {
        pathClear,
        pathBlocked,
        pathBlockedAndBecomeCalled,
    }

    enum int biggestLargeAccelSpeedY = 12;
    final static int accel(int ysp) pure
    {
        return (ysp <= biggestLargeAccelSpeedY) ? 2 : (ysp < 32) ? 1 : 0;
    }

    bool splatUpsideDown() const { return false; }
    bool collideAfterMoving() const { return true; } // floater should not

    abstract Collision scanWall();
    abstract Collision onLandingWithoutSplatting();
    abstract void selectFrame();

private:
    /* General rules of ballistic flight:
     * We move during a frame until we hit something.
     * We move only in orthogonal steps, never diagonally. This makes the
     * collision code far easier because we can differentiate by direction.
     */
    final Collision moveSeveralTimes()
    {
        immutable int ySgn = speedY >= 0 ? 1 : -1;
        immutable int yAbs = speedY.abs;

        // Advance diagonally, examine collisions at each step.
        foreach (int step; 0 .. max(yAbs, speedX)) {
            Collision col = yAbs >= speedX
                ? // move ahead occasionally only, move down always
                kingXY((step + 1) * speedX / yAbs / 2 * 2
                     - (step)     * speedX / yAbs / 2 * 2, true)
                : // always move ahead 2-quantized, move down occasionally only
                kingXY(2 * (step % 2), ( (step + 1) * yAbs / speedX
                                       - (step)     * yAbs / speedX));
            if (col != Collision.pathClear)
                return col;
        }

        // In C++ Lix, tumblers and jumpers scanned terrain once more after
        // their final move. Floaters did not do that. That's inconsistent.
        // At least for jumpers & tumblers, checking the floor is good.
        // This mimicks closest the C++ Lix and D 0.8.x behavior.
        return collideAfterMoving() ? landOnFloor() : Collision.pathClear;
    }

    // We take ints instead of bools to allow a looser calling expression.
    final Collision kingXY(int wantMoveX, int wantMoveY)
    in {
        assert (wantMoveX == 0 || wantMoveX == 2, format("%d", wantMoveX));
        assert (wantMoveY == 0 || wantMoveY == 1, format("%d", wantMoveY));
    }
    body {
        Collision ret = Collision.pathClear;
        if (wantMoveY) {
            assert (speedY != 0);
            ret = speedY > 0 ? maybeMoveDown() : maybeMoveUp();
        }
        if (wantMoveX && ret == Collision.pathClear)
            ret = maybeMoveAhead();
        return ret;
    }

    final Collision maybeMoveDown()
    {
        immutable ret = landOnFloor();
        if (ret == Collision.pathClear) {
            moveDown(1);
            ++pixelsFallen;
        }
        return ret;
    }

    final Collision maybeMoveUp()
    {
        immutable ret = bumpCeiling();
        if (ret == Collision.pathClear) {
            moveUp(1);
            pixelsFallen = 0;
        }
        return ret;
    }

    final Collision maybeMoveAhead()
    {
        immutable ret = scanWall();
        if (ret == Collision.pathClear)
            moveAhead(2);
        return ret;
    }

    final Collision landOnFloor()
    {
        if (! isSolid(0, 2)) {
            return Collision.pathClear;
        }
        else if (pixelsFallen > pixelsSafeToFall && ! abilityToFloat) {
            immutable sud = this.splatUpsideDown();
            become(Ac.splatter);
            if (sud)
                lixxie.frame = 10;
            return Collision.pathBlockedAndBecomeCalled;
        }
        else {
            return onLandingWithoutSplatting();
        }
    }

    final Collision bumpCeiling()
    {
        if (solidWallHeight(0, 0) == 0) {
            return Collision.pathClear;
        }
        auto ret = Collision.pathBlocked;
        immutable newSpeedX = speedX / 2;
        if (ac != Ac.tumbler) {
            become(Ac.tumbler);
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
            tumbling.speedX = newSpeedX;
        }
        return ret;
    }
}
