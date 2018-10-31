module physics.physdraw.init;

import enumap;

import basics.alleg5;
import basics.globals;
import graphic.color;
import graphic.cutbit;
import graphic.internal;
import lix.skill.digger;
import lix.skill.cuber;
import net.ac; // To get builder brick length. No idea why that is in net.ac.
import net.style;
import physics.mask;
import physics.physdraw.algo;
import physics.terchang;

void deinitialize()
{
    foreach (enumVal, ref Albit sub; _subAlbits)
        if (sub !is null) {
            albitDestroy(sub);
            sub = null;
        }
    if (_mask) {
        albitDestroy(_mask);
        _mask = null;
    }
}

// Blergh function, it's gotten too long. It generates several masks
// and colorful bricks on the (_mask) bitmap.
// Maybe refactor into smaller private functions.
void initialize()
{
    // We need this only during Runmode.INTERACTIVE.
    // We don't need blittable VRAM bitmaps of the various masks.
    // Physics are in RAM entirely, physics masks are done by CTFE.
    version (tharsisprofiling)
        auto zoneInitialize = Zone(profiler, "physDraw initialize");
    assert (! _mask, "don't call physdraw.initialize() twice,"
        ~ " deinitialize first before you call this a second time");
    assert (masks.length, "please initialize game.masks before this");
    alias Type = TerrainDeletion.Type;
    alias rf   = al_draw_filled_rectangle;

    assert (builderBrickXl >= platformLongXl);
    assert (builderBrickXl >= platformShortXl);
    _mask = albitCreate(0x100, 0x80);
    assert (_mask, "couldn't create mask bitmap");

    auto targetBitmap = TargetBitmap(_mask);
    al_clear_to_color(color.transp);

    const recol = getInternal(basics.globals.fileImageStyleRecol).albit;
    if (! recol)
        throw new Exception("We lack the recoloring bitmap. "
            ~ "Is Lix installed properly? We're looking for: `"
            ~ basics.globals.fileImageStyleRecol.rootless ~ "'.");
    assert (recol.xl >= 3);

    auto lockRecol = LockReadOnly(recol);

    void drawBrick(in int x, in int y, in int xl,
        in Alcol light, in Alcol medium, in Alcol dark
    ) {
        alias yl = brickYl;
        rf(x,      y,      x+xl-1, y+1,  light);  // L L L L L M
        rf(x+1,    y+yl-1, x+xl,   y+yl, dark);   // M D D D D D
        rf(x,      y+yl-1, x+1,    y+yl, medium); // ^
        rf(x+xl-1, y,      x+xl,   y+1,  medium); //           ^
    }

    void drawCube(in int x, in int y,
        in Alcol light, in Alcol medium, in Alcol dark
    ) {
        alias l = Cuber.cubeSize;
        assert (l >= 10);
        rf(x, y, x+l, y+l, medium);

        void symmetrical(in int ax,  in int ay,
                         in int axl, in int ayl, in Alcol col)
        {
            rf(x + ax, y + ay, x + ax + axl, y + ay + ayl, col);
            rf(x + ay, y + ax, x + ay + ayl, y + ax + axl, col);
        }
        symmetrical(0, 0, l-1, 1, light);
        symmetrical(0, 1, l-2, 1, light);

        symmetrical(2, l-2, l-2, 1, dark);
        symmetrical(1, l-1, l-1, 1, dark);

        enum o  = 4; // offset of inner relief square from edge
        enum ol = l - 2*o - 1; // length of a single inner relief line
        symmetrical(o,   o,     ol, 1, dark);
        symmetrical(o+1, l-o-1, ol, 1, light);
    }

    // the first row of recol contains the file colors, then come several
    // rows, one per style < MAX.
    for (int i = 0; i < Style.max && i < recol.yl + 1; ++i) {
        Alcol getCol(in int x)
        {
            // DALLEGCONST: Function is not const-correct, we have to cast.
            return al_get_pixel(cast (Albit) recol, x, i+1);
        }
        drawBrick(i * builderBrickXl, 0, builderBrickXl,
            getCol(recol.xl - 3),
            getCol(recol.xl - 2),
            getCol(recol.xl - 1));
        drawBrick(i * platformLongXl, brickYl, platformLongXl,
            getCol(recol.xl - 3),
            getCol(recol.xl - 2),
            getCol(recol.xl - 1));
        drawBrick(i * platformShortXl, 2 * brickYl, platformShortXl,
            getCol(recol.xl - 3),
            getCol(recol.xl - 2),
            getCol(recol.xl - 1));
        drawCube(i * Cuber.cubeSize, cubeY,
            getCol(recol.xl - 3),
            getCol(recol.xl - 2),
            getCol(recol.xl - 1));
    }

    // digger swing
    rf(0, remY, Digger.tunnelWidth, remY + remYl, color.white);
    _subAlbits[Type.dig] = al_create_sub_bitmap(
        _mask, 0, remY, Digger.tunnelWidth, remY + remYl);

    void drawPixel(in int x, in int y, in Alcol col)
    {
        rf(x, y, x + 1, y + 1, col);
    }

    // basher and miner swings
    void drawSwing(in int startX, in int startY, in Type type)
    {
        foreach     (int y; 0 .. masks[type].solid.yl)
            foreach (int x; 0 .. masks[type].solid.xl)
                if (masks[type].solid.get(x, y))
                    drawPixel(startX + x, startY + y, color.white);

        assert (_subAlbits[type] is null);
        _subAlbits[type] = al_create_sub_bitmap(_mask, startX, startY,
                           masks[type].solid.xl, masks[type].solid.yl);
        assert (_subAlbits[type] !is null);
    }
    drawSwing(bashX,              remY, Type.bashRight);
    drawSwing(bashX +     bashXl, remY, Type.bashLeft);
    drawSwing(bashX + 2 * bashXl, remY, Type.bashNoRelicsRight);
    drawSwing(bashX + 3 * bashXl, remY, Type.bashNoRelicsLeft);
    drawSwing(mineX,              remY, Type.mineRight);
    drawSwing(mineX + mineXl,     remY, Type.mineLeft);

    // imploder, exploder
    drawSwing(implodeX, ploY, Type.implode);
    drawSwing(explodeX, ploY, Type.explode);
}
