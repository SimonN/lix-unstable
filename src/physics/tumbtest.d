module physics.tumbtest;

/*
 * Tumbler Test:
 *
 * A physics unittest to have the jumper jump against many different kinds
 * of terrain. Let's see if we can repro the sporadic March 27 crash from
 * 2022-03-27 with Dullstar, Rampoina, and me.
 */

version (unittest):

import basics.rect;
import physics.state;
import physics.statinit;
import level.level;
import net.style;
import net.permu;

unittest {
    auto sta = createTumblerTestState();
    sta.drawEnclosingSolidFrame();
    assert (sta.lookup.getSolidEven(Point(0, 0)));
}

GameState createTumblerTestState() {
    Level l = new Level();
    l.topology.resize(100, 100);
    auto sta = newZeroStateForPhysicsUnittest(l);
    return sta;
}

void drawEnclosingSolidFrame(ref GameState sta)
{
    foreach (int x; 0 .. sta.lookup.xl) {
        sta.lookup.setSolidAlreadyColored(Point(x, 0));
        sta.lookup.setSolidAlreadyColored(Point(x, 99));
    }
    foreach (int y; 0 .. sta.lookup.yl) {
        sta.lookup.setSolidAlreadyColored(Point(0, y));
        sta.lookup.setSolidAlreadyColored(Point(99, y));
    }
}

void addJumpingLix(ref GameState sta)
{
    Tribe* tr = Style.garden in sta.tribes;
    assert(tr !is null && *tr !is null);
    ####
}

