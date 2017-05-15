module lix.skill.blocker;

import std.math; // abs

import lix;
import game.tribe;

class Blocker : Job {

    enum forceFieldXlEachSide = 14;
    enum deadZoneForBuildersXl = 2; // dx >= this means no effect
    enum deadZoneForOthers = 0;
    enum forceFieldYlAbove = 16;
    enum forceFieldYlBelow = 8;

    mixin(CloneByCopyFrom!"Blocker");

    override @property bool blockable()   const { return false; }
    override PhyuOrder    updateOrder() const { return PhyuOrder.blocker; }

    override void perform()
    {
        if (! isSolid()) {
            become(Ac.faller);
            return;
        }
        else if (frame == 19) {
            frame = 4;
        }
        else if (isLastFrame) {
            // assignment (blocker -> walker): we remain blocker for a while,
            // and become a walker only at this point in time
            become(Ac.walker);
            return;
        }
        else {
            advanceFrame();
        }
        assert (lixxie.ac == Ac.blocker);
        blockOtherLix();
    }

    private final void blockOtherLix()
    {
        foreach (Tribe tribe; outsideWorld.state.tribes)
            foreach (Lixxie li; tribe.lixvec)
                if (li.job.blockable)
                    blockSingleLix(li);
    }

    private final void blockSingleLix(Lixxie li)
    {
        immutable int dx = env.distanceX(li.ex, this.ex);
        immutable int dy = env.distanceY(li.ey, this.ey);

        // li is inside the rectangular blocker force field?
        if (abs(dx) < forceFieldXlEachSide
            && dy > - forceFieldYlBelow
            && dy <   forceFieldYlAbove
        ) {
            immutable deadZoneXl = li.ac == Ac.builder
                ? deadZoneForBuildersXl : deadZoneForOthers;
            immutable blockedByR = li.facingLeft  && dx < -deadZoneXl;
            immutable blockedByL = li.facingRight && dx > deadZoneXl;
            if ((blockedByR || blockedByL) && ! li.turnedByBlocker) {
                li.turn();
                li.turnedByBlocker = true;
            }
            li.inBlockerFieldLeft = li.inBlockerFieldLeft || blockedByL;
            li.inBlockerFieldRight = li.inBlockerFieldRight || blockedByR;
        }
    }
}
// end class Blocker
