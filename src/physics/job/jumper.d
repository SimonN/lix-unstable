module physics.job.jumper;

import std.algorithm;
import std.range;

import physics.job;

class Jumper : BallisticFlyer {
public:
    override void onBecome(in Job old)
    {
        if (lixxie.abilityToRun) {
            speedX =   8;
            speedY = -12;
            frame  =  13; // 1 will be deducted from this
        }
        else {
            speedX =  6;
            speedY = -8;
        }
        for (int i = -4; i > -16; --i) {
            if (lixxie.isSolid(0, i)) {
                lixxie.become(Ac.stunner);
                return;
            }
        }
    }

protected:
    override bool wouldCollideAt(in Point ifFootWereAt) const
    {
        // by experiment with D Lix 0.8's convoluted tumbler code,
        // checking at -10 and not any higher lets us stickyclimb the same
        return iota(-10, 2).any!(
            y => lixxie.env.getSolidEven(ifFootWereAt + Point(0, y)));
    }

    override Collision onLandingWithoutSplatting()
    {
        immutable soft = speedY < 12;
        lixxie.become(Ac.lander);
        if (soft)
            lixxie.advanceFrame(); // of the landing anim
        return Collision.pathBlockedAndBecomeCalled;
    }

    override Collision reactToWall()
    {
        if (iota(-8, 2).any!(y => lixxie.isSolid(2, y)
                             && ! lixxie.isSolid(2, y-1))
        ) {
            lixxie.moveAhead(2);
            lixxie.become(Ac.ascender);
            // The ascender is smart enough to find the pixel by himself.
            return Collision.pathBlockedAndBecomeCalled;
        }
        else if (lixxie.abilityToClimb) {
            lixxie.become(Ac.climber);
            return Collision.pathBlockedAndBecomeCalled;
        }
        else {
            lixxie.turn();
            return Collision.pathBlocked;
        }
    }

    override void selectFrame()
    {
        if (lixxie.isLastFrame)
            frame = lixxie.abilityToRun ? 12 : frame - 1;
        else
            lixxie.advanceFrame();
    }
}
