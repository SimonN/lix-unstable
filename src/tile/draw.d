module tile.draw;

/* This belonged to Level originally. But it's useful everywhere, so it is
 * a global function now. This centralizes knowledge about TerOcc and Torbit.
 * TerOcc doesn't need to know about Torbit.
 */

import basics.alleg5; // blender
import graphic.color;
import graphic.cutbit;
import graphic.torbit;
import hardware.tharsis;
import tile.gadtile;
import tile.occur;
import tile.phymap;

void drawOccurrence(
    in TerOcc occ,
    in Point offset = Point(0, 0)
) {
    immutable Point pt = occ.loc + offset;
    if (! occ.dark) {
        version (tharsisprofiling)
            auto zone = Zone(profiler, "Level.drawPos VRAM normal");
        assert (occ.tile.cb);
        assert (occ.tile.cb.xfs == 1 && occ.tile.cb.yfs == 1);
        // We subvert the Cutbit drawing function for speed.
        // Terrain is guaranteed to have only one frame anyway.
        drawToTargetTorbit(occ.tile.cb.albit, pt, occ.mirrY, occ.rotCw);
    }
    else {
        version (tharsisprofiling)
            auto zone = Zone(profiler, "Level.drawPos VRAM dark");
        assert (occ.tile);
        assert (occ.tile.dark);
        with (BlenderMinus)
            drawToTargetTorbit(occ.tile.dark.albit, pt, occ.mirrY, occ.rotCw);
    }
}

void drawOccurrence(in TerOcc occ, Phymap lookup)
in {
    assert (lookup);
    assert (! occ.noow, "replace noow with groups before drawing");
}
do {
    version (tharsisprofiling)
        auto zone = Zone(profiler, "Level.drawPos RAM ");
    // The lookup map could contain additional info about trigger areas,
    // but drawPosGadget doesn't draw those onto the lookup map.
    // That's done by the game class.
    immutable xl = (occ.rotCw & 1) ? occ.tile.cb.yl : occ.tile.cb.xl;
    immutable yl = (occ.rotCw & 1) ? occ.tile.cb.xl : occ.tile.cb.yl;
    foreach (int y; occ.loc.y .. (occ.loc.y + yl))
        foreach (int x; occ.loc.x .. (occ.loc.x + xl)) {
            immutable p = Point(x, y);
            immutable bits = occ.phybitsOnMap(p);
            if (! bits)
                continue;
            else if (occ.dark)
                lookup.rm(p, Phybit.terrain | Phybit.steel);
            else {
                lookup.add(p, bits);
                if (! (bits & Phybit.steel))
                    lookup.rm(p, Phybit.steel);
            }
        }
}

void drawAllTriggerAreas(
    scope const ref GadOcc[][GadType.MAX] gadgets,
    Torbit target,
) {
    // We assume that our caller has set the drawing target to (target).
    foreach (oneList; gadgets) {
        foreach (g; oneList) {
            auto rect = g.triggerAreaOnMap;
            if (rect.xl == 0 && rect.yl == 0) {
                // Make it look nice for hatches, which only tell us a point.
                rect.x -= 1;
                rect.y -= 1;
                rect.xl = 3;
                rect.yl = 3;
            }
            else if (g.tile.type != GadType.water) {
                // Pretend to look for the bottom hi-res pixel of the
                // foot's lo-res pixel, not for the top hi-res pixel.
                rect.y += 1;
                /*
                 * Water won't pretend like this, which is inconsistent
                 * w.r.t. all other gadget types. The only real fix will be
                 * to change many tiles' trigger area definitions text files
                 * (a physics change) and then remove this hack, or to change
                 * how lix collide with triggers (also a physics change).
                 */
            }
            target.drawRectangle(rect, color.triggerArea);
        }
    }
}
