module physics.job.basher;

import std.algorithm; // min, max

import hardware.sound;
import physics.job;
import physics.mask;
import physics.terchang;

class Basher : Job {
public:
    int halfPixelsMovedDown; // per pixel down: += 2; per frame passed: -= 1;
    bool steelWasHit;

    enum halfPixelsToFall = 9;

    override PhyuOrder updateOrder() const { return PhyuOrder.remover; }

    override void onBecome(in Job old)
    {
        // September 2015: start faster to make the basher slightly stronger
        frame = 2;
    }

    override void perform()
    {
        lixxie.advanceFrame();
        if (frame == 7) {
            performSwing();
        }
        else if (frame == 10 && (steelWasHit || nothingMoreToBash)) {
            if (steelWasHit) {
                lixxie.turn();
            }
            lixxie.become(Ac.walker);
            return;
        }
        else if (frame >= 11 && frame < 16
            && ! lixxie.isSolid(2, 1) // Lix 0.11: Don't walk through terrain.
        ) {
            // This happens on 5 frames.
            lixxie.moveAhead();
        }
        // If we're walker/faller, we'll have returned from perform() already.
        // This can return again, but that's fine, no code after this.
        stopIfMovedDownTooFar();
    }

private:
    bool nothingMoreToBash()
    {
        // We don't check the pixels that would be in the upcoming basher
        // swing, but so far away that they will still be ahead of the lix
        // after a full basher's walk-ahead cycle. These pixels will be
        // checked after that next basher's walk cycle.
        // Checking everything would be a rectangle of 14+2, -16, 23+2, +1
        // instead of what we do,                      14+2, -14, 21+2, -3.
        // The +2 are changes from C++ Lix to account for the longer D mask.
        immutable earth = lixxie.countSolid(16, -14, 23, -3);
        if (earth < 15) {
            for (int x = 16; x <= 23; x += 2)
                if (lixxie.isSolid(x, -12))
                    return false; // Thin wall found. Keep bashing.
            return true; // No thin walls, too few pixels to continue bashing.
        }
        return false;
    }

    void performSwing()
    {
        bool omitRelics()
        {
            immutable earthAfter = lixxie.countSolid(16, -16, 17, 1);
            immutable pathClear  = nothingMoreToBash();
            return earthAfter == 0 && pathClear;
        }
        TerrainDeletion tc;
        tc.update = lixxie.outsideWorld.state.age;
        if (omitRelics) {
            tc.type = lixxie.facingRight
                ? TerrainDeletion.Type.bashNoRelicsRight
                : TerrainDeletion.Type.bashNoRelicsLeft;
        }
        else {
            tc.type = lixxie.facingRight
                ? TerrainDeletion.Type.bashRight
                : TerrainDeletion.Type.bashLeft;
        }
        tc.x = lixxie.ex - masks[tc.type].offsetX;
        tc.y = lixxie.ey - masks[tc.type].offsetY;
        lixxie.outsideWorld.physicsDrawer.add(tc);
        if (lixxie.wouldHitSteel(masks[tc.type])) {
            lixxie.playSound(Sound.STEEL);
            steelWasHit = true;
            // do not cancel the basher yet, this will happen later
        }
    }

    void stopIfMovedDownTooFar()
    {
        immutable stepSize = () {
            assert (this is lixxie.job, "memory corruption");
            assert (halfPixelsMovedDown < halfPixelsToFall, "bad math?");
            for (int y; 2*y < halfPixelsToFall - halfPixelsMovedDown; ++y)
                if (lixxie.isSolid(0, 2 + y))
                    return y;
            return -1;
        }();
        if (stepSize >= 0) {
            lixxie.moveDown(stepSize);
            halfPixelsMovedDown += 2 * stepSize;
            assert (halfPixelsMovedDown < halfPixelsToFall);
            if (halfPixelsMovedDown > 0)
                --halfPixelsMovedDown;
        }
        else {
            // was 3 in C++ Lix, but the walker uses 2, so we do that, too
            enum fallUpTo = 2;
            int y = 0;
            while (! lixxie.isSolid(0, 2 + y) && y < fallUpTo)
                ++y;
            if (lixxie.isSolid(0, 2 + y)) {
                lixxie.moveDown(y);
                lixxie.become(Ac.walker);
            }
            else
                Faller.becomeAndFallPixels(lixxie, y);
        }
    }
}
// end class Basher
