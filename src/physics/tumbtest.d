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

GameState createTumblerTestState() {
    Level l = new Level();
    l.topology.resize(100, 100);
    auto sta = newZeroState(l, [Style.garden], new Permu("0"));
    sta.drawEnclosingSolidFrame();
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

unittest {
    auto sta = createTumblerTestState();
    assert (sta.lookup.getSolidEven(Point(0, 0)));
}
