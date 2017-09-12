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
    override Collision onLandingWithoutSplatting()
    {
        immutable soft = speedY < 12;
        become(Ac.lander);
        if (soft)
            lixxie.advanceFrame(); // of the landing anim
        return Collision.pathBlockedAndBecomeCalled;
    }

    override Collision scanWall()
    {
        if (iota(-11, 2).all!(y => ! lixxie.isSolid(2, y))) {
            return Collision.pathClear;
        }
        else if (abilityToClimb) {
            become(Ac.climber);
            return Collision.pathBlockedAndBecomeCalled;
        }
        else if (iota(-8, 2).any!(y => lixxie.isSolid(2, y)
                                  && ! lixxie.isSolid(2, y-1))
        ) {
            moveAhead(2);
            become(Ac.ascender); // Ascender is smart enough to find the pixel
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
