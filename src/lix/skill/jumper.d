module lix.skill.jumper;

import std.algorithm;
import std.range;

import lix;

class Jumper : BallisticFlyer {
    mixin JobChild;

    override void onBecome(in Job old)
    {
        if (abilityToRun) {
            speedX =   8;
            speedY = -12;
            frame  =  13; // 1 will be deducted from this
        }
        else {
            speedX =  6;
            speedY = -8;
        }
        for (int i = -4; i > -16; --i)
            if (isSolid(0, i)) {
                become(Ac.stunner);
                return;
            }
    }

protected:
    override bool wouldCollideAt(in Point foot) const
    {
        // by experiment with D Lix 0.8's convoluted tumbler code,
        // checking at -10 and not any higher lets us stickyclimb the same
        return iota(-10, 2).any!(
            y => lixxie.env.getSolidEven(foot + Point(0, y)));
    }

    override Collision onLandingWithoutSplatting()
    {
        immutable soft = speedY < 12;
        become(Ac.lander);
        if (soft)
            lixxie.advanceFrame(); // of the landing anim
        return Collision.pathBlockedAndBecomeCalled;
    }

    override Collision reactToWall()
    {
        if (iota(-8, 2).any!(y => lixxie.isSolid(2, y)
                             && ! lixxie.isSolid(2, y-1))
        ) {
            moveAhead(2);
            become(Ac.ascender); // Ascender is smart enough to find the pixel
            return Collision.pathBlockedAndBecomeCalled;
        }
        else if (abilityToClimb) {
            become(Ac.climber);
            return Collision.pathBlockedAndBecomeCalled;
        }
        else {
            turn();
            return Collision.pathBlocked;
        }
    }

    override void selectFrame()
    {
        if (isLastFrame)
            frame = (abilityToRun ? 12 : frame - 1);
        else
            advanceFrame();
    }
}
