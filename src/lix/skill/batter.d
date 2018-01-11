module lix.skill.batter;

import std.math;
import std.range;

import basics.rect;
import hardware.sound;
import lix;
import physics.tribe;

class Batter : Job {
    mixin JobChild;

    enum flingAfterFrame = 2;
    enum flingSpeedX =  10;
    enum flingSpeedY = -12;

    override @property bool blockable() const { return false; }

    override PhyuOrder updateOrder() const
    {
        if (frame == flingAfterFrame) return PhyuOrder.flinger;
        else                          return PhyuOrder.peaceful;
    }

    override void perform()
    {
        if (! isSolid) {
            become(Ac.faller);
            return;
        }
        else if (isLastFrame) {
            become(Ac.walker);
            return;
        }
        if (updateOrder == PhyuOrder.flinger)
            flingEverybody();
        advanceFrame();
    }

private:
    void flingEverybody()
    {
        bool hit = false;
        foreach (Tribe battedTribe; outsideWorld.state.tribes)
            foreach (id, Lixxie target; battedTribe.lixvec.enumerate!int) {
                if (! shouldWeFling(target))
                    continue;
                hit = true;
                fling(target, id);
            }
        // Both the hitter and the target will play the hit sound.
        // This hitting sound isn't played even quietly if an enemy lix
        // hits an enemy lix, but we want the sound if we're involved.
        lixxie.playSound(hit ? Sound.BATTER_HIT : Sound.BATTER_MISS);
    }

    bool shouldWeFling(in Lixxie target)
    {
        if (! target.healthy)
            return false;

        Rect sweetZone = Rect(ex - 12 + 6 * dir, ey - 16, 26, 25);
        if (target.ac == Ac.blocker) {
            // The -6 is because we already start with +6*dir.
            // The -2 is because the blocker field excludes its boundary
            // but our sweetZone is inclusive on the left. While sweetZone is
            // exclusive on the right, sweetZone was already enlarged by 2
            // over C++ Lix's flingbox that was inclusive on both sides.
            // (We have width 26, C++ Lix had 24.)
            enum extraBackward = Blocker.forceFieldXlEachSide - 6 - 2;
            enum extraForward = 4; // was 6 in C++. That didn't touch blocker.
            static assert (extraBackward > 0);
            sweetZone.x -= facingRight ? extraBackward : extraForward;
            sweetZone.xl += extraBackward + extraForward;
        }
        return env.isPointInRectangle(Point(target.ex, target.ey), sweetZone)
            && lixxie !is target
            // Do not allow the same player's batters to bat each other.
            // This is important for singleplayer: two lixes shall not be able
            // to travel together without any help, one shall stay behind.
            // Solution: If we already have a fling assignment, probably
            // from other batters, we cannot bat batters from our own tribe.
            && ! (this.flingNew && target.style == this.style
                    && target.ac == Ac.batter && target.frame == frame);
    }

    void fling(Lixxie target, in int targetId)
    {
        target.addFling(flingSpeedX * dir, flingSpeedY, style == target.style);
        assert (outsideWorld);
        if (outsideWorld.effect)
            outsideWorld.effect.addSound(lixxie.outsideWorld.state.update,
                Passport(target.style, targetId), Sound.BATTER_HIT);
    }
}
