module physics.physdraw.algo;

/*
 * Free functions that will be called from the LandDrawers.
 * Some global state that mutates whenever the screen resolution changes.
 * All this should not be imported from outside the phydraw package.
 */

import std.algorithm;
import std.conv;

import enumap;

import basics.alleg5;
import graphic.color;
import graphic.torbit;
import hardware.tharsis;
import lix.skill.cuber;
import lix.skill.digger;
import net.ac; // To get builder brick length. No idea why that is in net.ac.
import net.repdata;
import physics.mask;
import physics.terchang;
import tile.phymap;

package:

/*
 * All lix styles share one large source VRAM bitmap with the masks and bricks
 * in their many colors.
 */
static Albit _mask;

/*
 * Constants and functions that behave like constants once the physics masks
 * have been initialized.
 * Enumap _subAlbits is used by the terrain removers, not by the styled adders
 */
static Enumap!(TerrainDeletion.Type, Albit) _subAlbits;

enum buiY  = 0;
enum cubeY = 3 * brickYl;
enum remY  = cubeY + Cuber.cubeSize;
enum remYl = 32;
enum ploY  = remY + remYl;
int ploYl() { return masks[TerrainDeletion.Type.implode].solid.yl; }
enum bashX  = Digger.tunnelWidth + 1;
int bashXl() { return masks[TerrainDeletion.Type.bashRight].solid.xl + 1; }
int mineX() { return bashX + 4 * bashXl; } // 4 basher masks
int mineXl() { return masks[TerrainDeletion.Type.mineRight].solid.xl + 1; }
enum implodeX = 0;
int explodeX() { return masks[TerrainDeletion.Type.implode].solid.xl + 1; }

///////////////////////////////////////////////////////////////////////////////

/*
 * Helper functions that do not yet affect any phymap or land
 */
version (assert) {
    import std.string;
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
}

/*
 * Split source array into two halves: Head: == current update, Tail: > upd.
 * Change the source array at the call site to be the tail half.
 * Return the head half that was split off.
 */
T[] splitOffFromArray(T)(ref T[] arr, in Phyu upd) pure nothrow @nogc
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

///////////////////////////////////////////////////////////////////////////////

/*
 * "Stamping" means to copy the interesting Phybits to a Phymap.
 * "Drawing" means to draw the change to a land.
 * Stamp the TerrainDeletion to the Phymap. Return the FlaggedDeletion (based
 * on the TerrainDeletion) that our caller might want draw onto the land later.
 */
FlaggedDeletion stampTo(in TerrainDeletion tc, Phymap phymap)
{
    version (tharsisprofiling)
        auto zone = Zone(profiler, format("PhysDraw lookup %s",
            tc.type.to!string));
    int steelHit = 0;
    if (tc.type == TerrainDeletion.Type.dig)
        steelHit = diggerAntiRazorsEdge!true(phymap, tc);
    else
        steelHit += phymap.setAirCountSteelEvenWhereMaskIgnores(
                        tc.loc, masks[tc.type]);
    return FlaggedDeletion(tc, steelHit > 0);
}

/*
 * Stamp a digger mask to the phymap, then returns if steel was hit.
 * (Returns true even if steel was hit during the mask's steel tolerance
 * that would cancel a working lix.)
 *
 * Or: Draw a digger mask to the land. Return false.
 * Does not take the land as an argument, land is implicit because of A5's
 * thread-global bitmap targeting. Takes Phymap to see where to draw on land.
 *
 * Reason for this special function instead of the normal stampTo:
 * The digger can't call the regular setAirCountSteel in a rectangle.
 * Reason: Steel in pixel p affects whether the digger tries to remove
 * earth in a pixel p' left or right of p.
 * As usualy, any steel in the mask requires the land-drawing later to
 * draw pixel-by-pixel. But for the digger, even the land-drawing must
 * go through diggerAntiRazorsEdge again if it's pixel-by-pixel!
 */
bool diggerAntiRazorsEdge(
    bool toPhymap, // true if we're drawing to phymap, false if to land
    P, T // see the template if constraint; these depend completely on toPhymap
)(
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

/*
 * Draw a FlaggedDeletion to the land, according to the passed Phymap.
 * Compatible with already-halted bitmap drawing.
 *
 * Assumes that the land is target torbit and A5's drawing target.
 * The land, therefore, is not passed explicitly into this function anymore.
 */
void drawToLand(in FlaggedDeletion tc, in Phymap phymap)
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

///////////////////////////////////////////////////////////////////////////////

/*
 * Draw a sprite from an Albit onto the land.
 * Compatible with already-held bitmap drawing.
 *
 * The Phymap and the FlaggedDeletion decide whether it's drawn all at once
 * (fastest) or whether and where it must be drawn pixel-by-pixel.
 */
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
    foreach (y; 0 .. sprite.yl) {
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
}   }   }   }

/*
 * Stamp a queued terrain addition to the phymap. Does not modify any land.
 * Returns the FlaggedAddition that our callers might want to draw onto
 * some land later.
 */
FlaggedAddition stampTo(in TerrainAddition tc, Phymap phymap)
{
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
    return fc;
}

void drawToLand(in FlaggedAddition tc, in Phymap phymap)
{
    mixin AdditionsDefs;
    Albit sprite = al_create_sub_bitmap(_mask, x, y, xl, yl);
    scope (exit)
        albitDestroy(sprite);
    spriteToLand(phymap, tc, sprite);
}

/*
 * Private: Template that is instantiated in some of the above functions.
 * Expects an argument called tc in the function where it's instantiated.
 */
private:

mixin template AdditionsDefs() {
    immutable build = (tc.type == TerrainAddition.Type.build);
    immutable plaLo = (tc.type == TerrainAddition.Type.platformLong);
    immutable plaSh = (tc.type == TerrainAddition.Type.platformShort);
    immutable yl = (build || plaLo || plaSh) ? net.ac.brickYl
                                             : tc.cubeYl;
    immutable y  = build ? 0
                 : plaLo ? 1 * net.ac.brickYl
                 : plaSh ? 2 * net.ac.brickYl
                 : cubeY + Cuber.cubeSize - yl;
    immutable xl = build ? net.ac.builderBrickXl
                 : plaLo ? net.ac.platformLongXl
                 : plaSh ? net.ac.platformShortXl
                 :         Cuber.cubeSize;
    immutable x  = xl * tc.style;
}
