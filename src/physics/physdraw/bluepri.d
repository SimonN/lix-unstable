module physics.physdraw.bluepri;

/*
 * This doesn't commit any changes to physics maps or the state's land.
 */

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
}
