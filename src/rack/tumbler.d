module physics.rack.tumbler;

import basics.rect;
import tile.phymap;

class TumblerTest {
    Phymap createMap()
    {
        auto ret = new Phymap(100, 100);
        foreach (int x; 0 .. 100) {
            ret.add(Point(x, 80), Phybit.terrain);
        }
        return ret;
    }
}
