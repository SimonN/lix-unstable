module physics.job.miner;

import std.algorithm; // max

import hardware.sound;
import physics.job;
import physics.mask;
import physics.terchang;

class Miner : Job {
private:
    /*
     * Counts how many pixels the miner has been moved down during the frames
     * where the lix is not moving forward. This can happen due to terrain
     * being removed below the lix. When this exceeds +4, the miner stops.
     *
     * It's reset to 0 after a miner swing.
     */
    int _yAwayFromIdealSlope = 0;

public:
    override PhyuOrder updateOrder() const { return PhyuOrder.remover; }

    override void perform()
    {
        lixxie.advanceFrame();
        moveDownIfSomebodyElseRemovedOurGround();
        if (lixxie.ac == Ac.faller) {
            return;
        }

        if (frame == 2) {
            _yAwayFromIdealSlope = 0;
            removeEarth();
        }
        else if (frame == 7 || frame == 8 || frame == 10 || frame == 11) {
            moveDiagonally();
        }
    }

private:
    void moveDownIfSomebodyElseRemovedOurGround()
    {
        enum cancelDepth = 4;
        int airBelow = 0;
        while (airBelow < cancelDepth && ! lixxie.isSolid(0, 2 + airBelow)) {
            ++airBelow;
        }
        _yAwayFromIdealSlope += airBelow;
        if (_yAwayFromIdealSlope >= cancelDepth) {
            lixxie.become(Ac.faller);
            return;
        }
        lixxie.moveDown(airBelow);
    }

    void removeEarth()
    {
        TerrainDeletion tc;
        tc.update = lixxie.outsideWorld.state.age;
        tc.type = lixxie.facingRight
            ? TerrainDeletion.Type.mineRight : TerrainDeletion.Type.mineLeft;
        tc.x = lixxie.ex - masks[tc.type].offsetX;
        tc.y = lixxie.ey - masks[tc.type].offsetY;
        lixxie.outsideWorld.physicsDrawer.add(tc);
        if (lixxie.wouldHitSteel(masks[tc.type])) {
            lixxie.outsideWorld.effect.addPickaxe(
                lixxie.outsideWorld.state.age,
                lixxie.outsideWorld.passport, lixxie.foot, lixxie.dir);
            lixxie.turn();
            lixxie.become(Ac.walker);
        }
    }

    void moveDiagonally()
    {
        if (! lixxie.isInbounds(2, 0)) {
            // Make it look nice. It's okay to walk into out-of-bounds terrain.
            lixxie.moveAhead();
            lixxie.moveDown(1);
            return;
        }
        if (lixxie.isSolid(2, 1) || lixxie.isSolid(2, 2)) {
            return; // We're in front of new terrain. Can't move diagonally.
        }

        lixxie.moveAhead();
        // Now, there is at least one pixel of air under our foot.

        if (_yAwayFromIdealSlope > 0) {
            lixxie.become(Ac.faller);
            return;
        }
        if (lixxie.isSolid(0, 3)) {
            lixxie.moveDown(1); // This is the most common case.
            return;
        }
        if (_yAwayFromIdealSlope <= 0 && lixxie.isSolid(0, 4)) {
            /*
             * Coarse bridge leeway: When the miner walks down a builder's
             * bridge, the bridge has slope 4x2 and is coarser than the ideal
             * slope, even though the angle is the same. This leeway makes the
             * coarse bridge feel like the ideal slope. But don't allow two
             * leeway steps in succession, that would be 45-degree downsteps.
             */
            lixxie.moveDown(2); // Step down a builder's brick.
            ++_yAwayFromIdealSlope; // Prevent successive leeway downsteps.
            return;
        }
        Faller.becomeAndFallPixels(lixxie, 1);
    }
}
