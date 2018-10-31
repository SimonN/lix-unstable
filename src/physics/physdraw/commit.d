module physics.physdraw.commit;

/* PhysicsCommitter: responsible for adding/removing terrain on the level
 * torbit during a game and to the physics map. This will affect physics,
 * it is not designed for mere blueprinting of future physics changes.
 *
 * This doesn't render the level at start of game.
 *
 * Has capabilities to cache drawing instructions and then perform then all
 * at once. Drawing to torbit can be disabled, to get only drawing onto the
 * lookup map, for automatic replay verification.
 *
 * All lix styles share one large source VRAM bitmap with the masks and bricks
 * in their many colors.
 *
 * Convention in storing coordinates: Lix activities are expected to pass
 * the coordinates of the terrain changes' top-left corners. They do not pass
 * their own ex/ey. This is different from what Lix do for effects stored
 * in the EffectManager.
 */

import std.array;
import std.algorithm;
import std.conv;
import std.functional;
import std.range;
import std.string;

import enumap;

import basics.alleg5;
import basics.cmdargs;
import basics.globals;
import basics.help;
import net.repdata;
import tile.phymap;
import graphic.color;
import graphic.cutbit;
import graphic.torbit;
import graphic.internal; // must be initialized first
import hardware.tharsis;
import lix.skill.cuber; // Cuber.cubeSize
import lix.skill.digger; // diggerTunnelWidth
import net.ac;
import net.style;
import physics.mask;
import physics.physdraw.base;
import physics.terchang;

class PhysicsCommitter : LandDrawer {
    // Stage a physics change for the next call to apply*().
    void add(in TerrainAddition tc) { _addsForPhymap ~= tc; }
    void add(in TerrainDeletion tc) { _delsForPhymap ~= tc; }

    void applyChangesToPhymap(Phymap pm)
    {
        deletionsToPhymap(pm);
        additionsToPhymap(pm);
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



// ############################################################################
// ############################################################################
// ############################################################################



private:
    TerrainDeletion[] _delsForPhymap;
    TerrainAddition[] _addsForPhymap;

    FlaggedDeletion[] _delsForLand;
    FlaggedAddition[] _addsForLand;

    void assertChangesForLand(T)(T[] arr, in Phyu upd)
    {
        // Functions calling assertChangesForLand need not be called on each
        // update, but only if the land must be drawn like it should appear
        // now. In noninteractive mode, this shouldn't be called at all.
        assert (_mask);
        assert (isSorted!"a.update < b.update"(arr));
        assert (arr == null || arr[0].update >= upd, format("There are "
            ~ "additions to the land that should be drawn in the earlier "
            ~ "update %d. Right now we have update %d. If this happens after "
            ~ "loading a savestate, empty all queued additions/deletions.",
            arr[0].update, upd));
    }

    T[] splitOffFromArray(T)(ref T[] arr, in Phyu upd)
    {
        // Split the queue into what needs to be processed during this call,
        // remove these from the caller's queue (arr).
        int cut = 0;
        while (cut < arr.length && arr[cut].update == upd)
            ++cut;
        auto ret = arr[0 .. cut];
        arr      = arr[cut .. $];
        return ret;
    }



// ############################################################################
// ############################################################################
// ############################################################################



    void deletionsToPhymap(Phymap phymap)
    in { assert (_delsForPhymap.all!(tc =>
        tc.update == _delsForPhymap[0].update));
    }
    out { assert (_delsForPhymap == null); }
    body {
        version (tharsisprofiling)
            auto zone = Zone(profiler, format("PhysDraw del lookup %dx",
                _delsForPhymap.len));
        scope (exit)
            _delsForPhymap = null;

        foreach (const tc; _delsForPhymap) {
            version (tharsisprofiling)
                auto zone2 = Zone(profiler, format("PhysDraw lookup %s",
                    tc.type.to!string));
            int steelHit = 0;
            if (tc.type == TerrainDeletion.Type.dig)
                steelHit = diggerAntiRazorsEdge!true(phymap, tc);
            else
                steelHit += phymap.setAirCountSteelEvenWhereMaskIgnores(
                                tc.loc, masks[tc.type]);
            _delsForLand ~= FlaggedDeletion(tc, steelHit > 0);
        }
    }

    // The digger can't call the regular setAirCountSteel in a rectangle.
    // Reason: Steel in pixel p affects whether the digger tries to remove
    // earth in a pixel p' left or right of p.
    // As usualy, any steel in the mask requires the land-drawing later to
    // draw pixel-by-pixel. But for the digger, even the land-drawing must
    // go through diggerAntiRazorsEdge again if it's pixel-by-pixel!
    bool diggerAntiRazorsEdge(bool toPhymap, P, T)(
        P phymap, // check this for steel, and change it where no steel is
        in T tc // the queued change
    )
        if (toPhymap && is (T == TerrainDeletion) && is (P == Phymap)
        || !toPhymap && is (T == FlaggedDeletion) && is (P == const(Phymap)))
    in { assert (tc.type == TerrainDeletion.Type.dig); }
    body {
        bool ret = false;
        Point p;
        for (p.y = 0; p.y < tc.digYl; ++p.y) {
            enum string digCheck = toPhymap ? q{
                if (phymap.setAirCountSteel(tc.loc + p)) {
                    ret = true;
                    break;
                }
            } : q{
                if (phymap.getSteel(tc.loc + p))
                    break;
                // Assume we're in subtractive drawing mode: white erases.
                // Assume that the land (which isn't arg-passed into here)
                // is the current target bitmap, and that it has the same
                // torus properties as the Phymap (Topology.matches == true).
                auto wrapped = phymap.wrap(tc.loc + p);
                al_draw_pixel(wrapped.x + 0.5f, wrapped.y + 0.5f, color.white);
            };
            enum int half = Digger.tunnelWidth / 2;
            for (p.x = half - 1; p.x >= 0; --p.x) { mixin(digCheck); }
            for (p.x = half; p.x < 2*half; ++p.x) { mixin(digCheck); }
        }
        return ret;
    }

    void deletionsToLandForPhyu(in Phymap phymap, in Phyu upd)
    in {
        assertChangesForLand(_delsForLand, upd);
        // And assume that land (that isn't passed into here) is draw-target.
    }
    out {
        assert (_delsForLand == null
            ||  _delsForLand[0].update > upd);
    }
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
                deletionToLand(phymap, tc);
        }
    }

    void deletionToLand(in Phymap phymap, in FlaggedDeletion tc)
    {
        assert (al_is_bitmap_drawing_held());
        version (tharsisprofiling)
            auto zone = Zone(profiler, format("PhysDraw land %s",
                tc.type.to!string));
        if (tc.type != TerrainDeletion.Type.dig)
            spriteToLand(phymap, tc, _subAlbits[tc.type]);
        else if (tc.drawPerPixelDueToSteel)
            diggerAntiRazorsEdge!false(phymap, tc);
        else {
            // digging height is variable length. Generate correct bitmap.
            assert (tc.type == TerrainDeletion.Type.dig);
            assert (tc.digYl > 0);
            Albit sprite = al_create_sub_bitmap(_mask,
                0, remY, Digger.tunnelWidth, tc.digYl);
            spriteToLand(phymap, tc, sprite);
            albitDestroy(sprite);
        }
    }

    void spriteToLand(T)(
        in Phymap phymap, // Required to determine which pixels to draw.
        in T tc, // The change that is to be drawn to the land
        Albit sprite // The sprite of that change, likely sub-bitmap of _mask
    )
        if (is (T == FlaggedDeletion) || is (T == FlaggedAddition))
    in {
        assert (al_is_bitmap_drawing_held());
        assert (sprite);
        assert (phymap);
        // Assert that Torbit land (that isn't passed into here)
        // is the target Torbit and also A5's target bitmap.
    }
    body {
        static if (is (T == FlaggedDeletion))
            immutable bool allAtOnce = ! tc.drawPerPixelDueToSteel;
        else
            immutable bool allAtOnce = ! tc.drawPerPixelDueToExistingTerrain;
        if (allAtOnce) {
            version (tharsisprofiling)
                auto zone = Zone(profiler, format("PhysDraw pix-all %s",
                                                  tc.type.to!string));
            sprite.drawToTargetTorbit(tc.loc);
            return;
        }
        // We continue here only if we must draw per pixel, not all at once.
        // We aren't a digger: Per-pixel-diggers don't even enter
        // spriteToLand, instead they're dispatched by deletionToLand
        // directly to the digger-anti-razor-edging.
        version (tharsisprofiling)
            auto zone = Zone(profiler, format("PhysDraw pix-one %s",
                                              tc.type.to!string));
        foreach (y; 0 .. sprite.yl)
            foreach (x; 0 .. sprite.xl) {
                immutable fromPoint = Point(x, y);
                immutable toPoint   = tc.loc + fromPoint;
                static if (is (T == FlaggedDeletion)) {
                    if (! phymap.getSteel(toPoint))
                        sprite.singlePixelToTargetTorbit(fromPoint, toPoint);
                }
                else {
                    if (tc.needsColoring[y][x])
                        sprite.singlePixelToTargetTorbit(fromPoint, toPoint);
                }
            }
    }

// ############################################################################
// ############################################################################
// ############################################################################



    void
    additionsToPhymap(Phymap phymap)
    in { assert(_addsForPhymap.all!(
        tc => tc.update == _addsForPhymap[0].update));
    }
    out {
        assert (_addsForPhymap == null);
    }
    body {
        foreach (const tc; _addsForPhymap) {
            version (tharsisprofiling)
                auto zone = Zone(profiler, "PhysDraw lookupmap "
                                           ~ tc.type.to!string);
            mixin AdditionsDefs;
            assert (yl > 0, format("%s queued with yl <= 0; yl = %d",
                tc.type.to!string, yl));
            // If land exists, remember the changes to be able to draw them
            // later. No land in noninteractive mode => needn't save this.
            // We still create it properly... to keep my code short. <_<;;
            auto fc = FlaggedAddition(tc);
            foreach (int y; 0 .. yl)
                foreach (int x; 0 .. xl) {
                    Point target = tc.loc + Point(x, y);
                    if (phymap.getSolid(target))
                        fc.drawPerPixelDueToExistingTerrain = true;
                    else {
                        phymap.add(target, Phybit.terrain);
                        fc.needsColoring[y][x] = true;
                    }
                }
            _addsForLand ~= fc;
        }
        _addsForPhymap = null;
    }

    void additionsToLandForPhyu(in Phymap phymap, in Phyu upd)
    in { assertChangesForLand(_addsForLand, upd); }
    out {
        assert (_addsForLand == null
            ||  _addsForLand[0].update > upd);
    }
    body {
        auto processThese = splitOffFromArray(_addsForLand, upd);
        if (processThese == null)
            return;
        al_hold_bitmap_drawing(true);
        scope (exit)
            al_hold_bitmap_drawing(false);
        foreach (const tc; processThese) {
            mixin AdditionsDefs;
            Albit sprite = al_create_sub_bitmap(_mask, x, y, xl, yl);
            spriteToLand(phymap, tc, sprite);
            albitDestroy(sprite);
        }
    }
}
