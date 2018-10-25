module physics.physdraw.bluepri;

/*
 * This doesn't commit any changes to physics maps or the state's land.
 */

import physics.physdraw.base;
import physics.terchang;
import tile.phymap;

class Blueprinter : LandDrawer {
private:
    Phymap _lookup; // we don't own it
    TerrainAddition[] _additions;
    TerrainDeletion[] _deletions;

public:
    this(Phymap lo) in { assert(lo); } body { _lookup = lo; }

    void add(in TerrainAddition tc) { _additions ~= tc; }
    void add(in TerrainDeletion tc) { _deletions ~= tc; }

    void apply()
    {
    }
}
