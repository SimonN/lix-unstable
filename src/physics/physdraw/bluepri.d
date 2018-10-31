module physics.physdraw.bluepri;

/*
 * This doesn't commit any changes to physics maps or the state's land.
 */

import std.range;

import basics.alleg5;
import graphic.torbit;
import physics.physdraw.algo;
import physics.physdraw.base;
import physics.terchang;
import tile.phymap;

class Blueprinter : LandDrawer {
private:
    TerrainAddition[] _additions;
    TerrainDeletion[] _deletions;

public:
    void add(in TerrainAddition tc) { _additions ~= tc; }
    void add(in TerrainDeletion tc) { _deletions ~= tc; }

    bool anyChangesToLand() const pure nothrow @nogc
    {
        return ! _additions.empty || ! _deletions.empty;
    }
    /*
     * This method does everything with the queued adds/dels.
     * This method has many conceptual problems:
     *  1.  The phymap is never changed. A long miner cannot react to basher
     *      tunnels that will cross his patch later during his work.
     *      The miner's blueprint will assume no basher.
     *  2.  If we simulated all lixes, not merely the miner, then the basher
     *      would blueprint her tunnel, too.
     */
    void drawAllChangesToTorbitClobberingThePhymap(Phymap phymap, Torbit land)
    in {
        assert (phymap, "Blueprinter needs a Phymap to draw w.r.t. steel");
        assert (land, "Blueprinter needs a Torbit to draw");
        assert (land.albit, "Blueprinter needs an undestroyed Torbit");
    }
    out { assert (! anyChangesToLand); }
    body {
        if (! anyChangesToLand)
            return;
        auto target = TargetTorbit(land);
        while (anyChangesToLand) {
            if (nextIsDeletion)
                drawSomeDeletions(phymap);
            else
                drawSomeAdditions(phymap);
        }
    }

private:
    // Hm, we hardcode here the rule that deletions always come first
    // in the same phyu, before additions. This violates DRY.
    // This should be expressed only in the lix performances.
    bool nextIsDeletion() const pure nothrow @nogc
    in { assert (anyChangesToLand, "Don't query the next type if no next"); }
    body {
        return _additions.empty ? true
            : _deletions.empty ? false
            : _deletions[0].update <= _additions[0].update;
    }

    void drawSomeDeletions(Phymap phymap)
    in {
        assert (anyChangesToLand);
        assert (nextIsDeletion);
        // Also assume that the land (not passe into here) is target torbit.
    }
    body {
        // Dont use "with (BlenderMinus) {" because the "land" (blueprint
        // canvas) is already transparent. We should really erase the terrain,
        // but that seems hard to realize. Need more thinking!
        al_hold_bitmap_drawing(true);
        scope (exit)
            al_hold_bitmap_drawing(false);
        while (anyChangesToLand && nextIsDeletion) {
            _deletions[0].stampTo(phymap).drawToLand(phymap);
            _deletions = _deletions[1 .. $];
        }
    }

    void drawSomeAdditions(Phymap phymap)
    in {
        assert (anyChangesToLand);
        assert (! nextIsDeletion);
        // Also assume that the land (not passe into here) is target torbit.
    }
    body {
        al_hold_bitmap_drawing(true);
        scope (exit)
            al_hold_bitmap_drawing(false);
        while (anyChangesToLand && ! nextIsDeletion) {
            _additions[0].stampTo(phymap).drawToLand(phymap);
            _additions = _additions[1 .. $];
        }
    }
}
