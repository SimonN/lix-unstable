module physics.physdraw.base;

/*
 * Interface to pass to lixes during their perform().
 *
 * Convention in storing coordinates: Lix activities are expected to pass
 * the coordinates of the terrain changes' top-left corners. They do not pass
 * their own ex/ey. This is different from what Lix do for effects stored
 * in the EffectManager.
 */

import physics.terchang;

interface LandDrawer {
public:
    // Override these two in the subclass. The skills will use no other
    // interface than these two.
    void add(in TerrainAddition tc);
    void add(in TerrainDeletion tc);
}
