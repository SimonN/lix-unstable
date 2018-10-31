module physics.physdraw.commit;

/* PhysicsCommitter: responsible for adding/removing terrain on the level
 * torbit during a game and to the physics map. This will affect physics,
 * it is not designed for mere blueprinting of future physics changes.
 *
 * This doesn't render the level at start of game.
 *
 * Has capabilities to cache drawing instructions and then perform then all
 * at once. Drawing to torbit can be disabled, to get only drawing onto the
 * lookup map, for automatic replay verification. The caller is required
 * to call us as follows:
 *  1. Call add() for a single phyu, maybe several times
 *  2. Call applyChangesToPhymap() once to stamp input for all phyus from (1.)
 *  3. Call add() for the same or a higher phyu, maybe several times
 *  4. Call applyChangesToPhymap() once to stamp
 *  5. Call add() for the same or a higher phyu, maybe several times
 *  6. Call applyChangesToPhymap() once to stamp
 *  ...
 *  9. Call applyChangesToLand() once you're ready to draw to the (VRAM) land.
 *      Pass the current phyu for debugging; it will make sure that you haven't
 *      computed further with the Phymap than you are now wanting to draw.
 */

import std.algorithm;
import std.range;

import basics.alleg5;
import graphic.cutbit;
import graphic.torbit;
import hardware.tharsis;
import net.repdata;
import physics.physdraw.algo;
import physics.physdraw.base;
import physics.terchang;
import tile.phymap;

class PhysicsCommitter : LandDrawer {
private:
    TerrainDeletion[] _delsForPhymap;
    TerrainAddition[] _addsForPhymap;

    FlaggedDeletion[] _delsForLand;
    FlaggedAddition[] _addsForLand;

public:
    // Stage a physics change for the next call to apply*().
    void add(in TerrainAddition tc) { _addsForPhymap ~= tc; }
    void add(in TerrainDeletion tc) { _delsForPhymap ~= tc; }

    void applyChangesToPhymap(Phymap pm)
    {
        changesToPhymap(_delsForPhymap, _delsForLand, pm);
        changesToPhymap(_addsForPhymap, _addsForLand, pm);
    }

    @property bool anyChangesToLand() const pure @nogc
    {
        return _delsForLand != null || _addsForLand != null;
    }

    // The single public function for any drawing to the land.
    // Should be understandable from the many asserts, otherwise ask me.
    // You should know what a lookup map is (class Phymap from tile.phymap).
    // land is the torus bitmap onto which we draw the terrain, but this
    // is never queried for physics -- that's what the lookup map is for.
    void applyChangesToLand(
        in Phymap phymap, // Required to determine pixels to draw to land
        Torbit land, // Draw changes (that are already on the Phymap) here
        in Phyu upd, // in Phyu upd: Pass current update of the game to this.
    )                // (upd) is only for asserts, no effect in release mode.
    in {
        assert (phymap);
        assert (land);
        enum msg = "You shouldn't draw to land when you still have changes "
            ~ "to be drawn to the lookup map. You may want to call "
            ~ "applyChangesToPhymap() more often.";
        assert (_delsForPhymap == null, msg);
        assert (_addsForPhymap == null, msg);
        enum msg2 = "applyChangesToLand() doesn't get called each update. "
            ~ "But there should never be something in there that isn't to be "
            ~ "processed during this call.";
        assert (_delsForLand == null || _delsForLand[$-1].update <= upd, msg2);
        assert (_addsForLand == null || _addsForLand[$-1].update <= upd, msg2);
    }
    out {
        assert (_delsForLand == null);
        assert (_addsForLand == null);
    }
    body {
        if (! anyChangesToLand)
            return;

        version (tharsisprofiling)
            auto zone = Zone(profiler, "applyChangesToLand >= 1");
        auto target = TargetTorbit(land);

        while (_delsForLand != null || _addsForLand != null) {
            // Do deletions for the first update, then additions for that,
            // then deletions for the next update, then additions, ...
            immutable Phyu earliestPhyu
                = _delsForLand != null && _addsForLand != null
                ? min(_delsForLand[0].update, _addsForLand[0].update)
                : _delsForLand != null
                ? _delsForLand[0].update : _addsForLand[0].update;

            assert (al_get_target_bitmap() == land.albit, "For performance, "
                ~ " set the drawing target to land outside of *ToLandForPhyu."
                ~ " Slow performance is a logic bug!");
            deletionsToLandForPhyu(phymap, earliestPhyu);
            additionsToLandForPhyu(phymap, earliestPhyu);
        }
    }

    // Like applyChangesToLand, but discards everything.
    // If you don't want a graphical output, discard all changes to land
    // after you've called applyChangesToPhymap.
    void discardChangesToLand()
    in {
        assert (_delsForPhymap == null, "Draw onto a Phymap first.");
        assert (_addsForPhymap == null, "Draw onto a Phymap first.");
    }
    body {
        _delsForLand = [];
        _addsForLand = [];
    }

///////////////////////////////////////////////////////////////////////////////

    /*
     * The source array has many changes. Stamp them onto the physics map.
     * Flag the changes according to how steel or existing terrain was met,
     * and append these flagged changes to the changes to be drawn to land.
     * We don't draw to land here yet.
     */
    void changesToPhymap(TC, FC)(
        ref TC[] source, // Changes to be stamped onto the Phymap
        ref FC[] dest, // Append flagged changes here. This needn't be empty.
        Phymap phymap
    )
        if ((is (TC == TerrainDeletion) && is (FC == FlaggedDeletion))
         || (is (TC == TerrainAddition) && is (FC == FlaggedAddition)))
    in { assert(source.all!(tc => tc.update == source[0].update)); }
    out { assert (source.empty); }
    body {
        foreach (const tc; source) {
            dest ~= tc.stampTo(phymap);
        }
        source = null;
    }

    void deletionsToLandForPhyu(in Phymap phymap, in Phyu upd)
    in {
        assertChangesForLand(_delsForLand, upd);
        // And assume that land (that isn't passed into here) is draw-target.
    }
    out { assert (_delsForLand == null ||  _delsForLand[0].update > upd); }
    body {
        auto processThese = splitOffFromArray(_delsForLand, upd);
        if (processThese == null)
            return;
        version (tharsisprofiling)
            auto zone = Zone(profiler, format("PhysDraw del land %dx",
                processThese.len));
        with (BlenderMinus) {
            al_hold_bitmap_drawing(true);
            scope (exit)
                al_hold_bitmap_drawing(false);
            foreach (const tc; processThese)
                tc.drawToLand(phymap);
        }
    }

    void additionsToLandForPhyu(in Phymap phymap, in Phyu upd)
    in {
        assertChangesForLand(_addsForLand, upd);
        // And assume that land (that isn't passed into here) is draw-target.
    }
    out { assert (_addsForLand == null || _addsForLand[0].update > upd); }
    body {
        auto processThese = splitOffFromArray(_addsForLand, upd);
        if (processThese == null)
            return;
        al_hold_bitmap_drawing(true);
        scope (exit)
            al_hold_bitmap_drawing(false);
        foreach (const(FlaggedAddition) fc; processThese) {
            fc.drawToLand(phymap);
        }
    }
}
