module physics.job.tumbler;

import std.algorithm;
import std.math;
import std.range;

import basics.help;
import physics.job;

class Tumbler : BallisticFlyer {
public:
    static applyFlingXY(Lixxie lix)
    {
        if (! lix.flingNew)
            return;
        immutable wantFlingX = lix.flingX;
        immutable wantFlingY = lix.flingY;
        lix.resetFlingNew();

        assert (lix.outsideWorld);
        if (wantFlingX != 0)
            lix.dir = wantFlingX;
        lix.become(Ac.tumbler);
        if (lix.ac == Ac.tumbler) {
            Tumbler tumbling = cast (Tumbler) lix.job;
            assert (tumbling);
            tumbling.speedX = wantFlingX.abs + (wantFlingX.abs & 1) ; // even
            tumbling.speedY = wantFlingY;
            tumbling.initPixelsFallen();
            tumbling.selectFrame();
            assert (tumbling.speedX % 2 == 0);
        }
        else
            assert (lix.ac == Ac.stunner, "should be the only possibility");
    }

    override void onBecome(in Job old)
    {
        if (lixxie.isSolid(0, 1) && old.ac == Ac.ascender)
            // unglitch out of wall, but only back and up
            // This is dumb, ideally the ascender shouldn't be inside the
            // terrain most of the time. And if it is still inside terrain
            // even after such an ascender rewrite, it's okay to stun inside
            // the terrain.
            for (int dist = 1; dist <= Walker.highestStepUp; ++dist) {
                if (! lixxie.isSolid(0, 1 - dist)) {
                    lixxie.moveUp(dist);
                    break;
                }
                else if (! lixxie.isSolid(- even(dist), 1)) {
                    lixxie.moveAhead(- even(dist));
                    break;
                }
            }

        if (lixxie.isSolid(0, 1)) {
            lixxie.become(Ac.stunner);
        }
        else if (old.ac == Ac.jumper) {
            this.copyFrom(cast (Jumper) old);
            this.frame = 3;
        }
        else
            selectFrame();
    }

protected:
    override bool splatUpsideDown() const { return this.frame >= 9; }

    override bool wouldCollideAt(in Point foot) const
    {
        return iota(-2, 2).any!(
            y => lixxie.env.getSolidEven(foot + Point(0, y)));
    }

    override Collision onLandingWithoutSplatting()
    {
        lixxie.become(Ac.stunner);
        return Collision.pathBlockedAndBecomeCalled;
    }

    override Collision reactToWall()
    {
        lixxie.turn();
        return Collision.pathBlocked;
    }

    override void selectFrame()
    {
        assert (speedX >= 0);
        immutable int tan = speedY * 12 / max(2, speedX);

        struct Result { int targetFrame; bool anim; }
        Result res =
              tan >  18 ? Result(13, true) // true = animate between 2 fames
            : tan >   9 ? Result(11, true)
            : tan >   3 ? Result( 9, true)
            : tan >   1 ? Result( 8)
            : tan >  -1 ? Result( 7)
            : tan >  -4 ? Result( 6)
            : tan > -10 ? Result( 5)
            : tan > -15 ? Result( 4)
            : tan > -30 ? Result( 3)
            : tan > -42 ? Result( 2)
            :             Result( 0, true);
        // unless we haven't yet selected frame from the midst of motion
        if (frame > 0)
            // ...never go forward through the anim too fast
            res.targetFrame = min(res.targetFrame, frame + (res.anim ? 2 : 1));

        frame = res.targetFrame
            + ((res.targetFrame == frame && res.anim) ? 1 : 0);
    }

private:
    void initPixelsFallen()
    {
        pixelsFallen = 0;
        if (speedY < 0)
            return;
        // In the check, ysp < speedY is correct, not ysp <= speedY.
        // Even if we begin with speedY == 2, we have fallen 0 pixels!
        // This is because we initialize with a speed, then use that speed
        // on the next physics update, only then increase the speed.
        // Thus, if we initialize speed with 2, we will fly 2 pixels down
        // on the next update and set speed to 4. Compared to speedY == 0,
        // we didn't fall more pixels before reaching speed 4, we merely
        // reached it sooner: The (speed == 0)-tumbler waited before falling.
        for (int ysp = speedY <= biggestLargeAccelSpeedY + 1 ? speedY % 2 : 0;
            ysp < speedY && accel(ysp) > 0;
            ysp += accel(ysp)
        ) {
            pixelsFallen += ysp;
        }
    }
}

unittest {
    auto t = new Tumbler();
    int wouldHaveFallen(int speed)
    {
        t.speedY = speed;
        t.initPixelsFallen();
        return t.pixelsFallen;
    }
    assert (wouldHaveFallen(0) == 0);
    assert (wouldHaveFallen(2) == 0);
    assert (wouldHaveFallen(4) == 2);
    assert (wouldHaveFallen(6) == 6);
    assert (wouldHaveFallen(8) == 12);
    assert (wouldHaveFallen(10) == 20);
    assert (wouldHaveFallen(12) == 30); // 12 is biggest speedY with accel == 2
    assert (wouldHaveFallen(14) == 42);
    assert (wouldHaveFallen(15) == 56);
    assert (wouldHaveFallen(16) == 71);
    assert (wouldHaveFallen(31) != wouldHaveFallen(32));
    assert (wouldHaveFallen(32) == wouldHaveFallen(33));
    assert (wouldHaveFallen(60) == wouldHaveFallen(80));

    assert (wouldHaveFallen(1) == 0);
    assert (wouldHaveFallen(3) == 1);
    assert (wouldHaveFallen(13) == 36); // in between values for 12 and 14

    for (int speed = 2; speed < 32; ++speed)
        assert (wouldHaveFallen(speed) < wouldHaveFallen(speed + 1));
}
