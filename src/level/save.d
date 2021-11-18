module level.save;

import std.algorithm;
import std.conv;
import std.stdio;
import std.string;

import glo = basics.globals;
import file.date;
import file.filename;
import file.io;
import file.log;
import graphic.color;
import level.level;
import tile.group;
import tile.occur;
import tile.abstile;

package void implSaveToFile(const(Level) level, in Filename fn)
{
    try {
        std.stdio.File file = fn.openForWriting();
        saveToFile(level, file);
        file.close();
    }
    catch (Exception e) {
        log(e.msg);
    }
}

public void saveToFile(const(Level) l, std.stdio.File file)
in { assert (l); }
do {
    file.writeln(IoLine.Dollar(glo.levelBuilt,       l.built      ));
    file.writeln(IoLine.Dollar(glo.levelAuthor,      l.author     ));
    if (l.nameGerman.length > 0)
        file.writeln(IoLine.Dollar(glo.levelNameGerman,  l.nameGerman ));
    file.writeln(IoLine.Dollar(glo.levelNameEnglish, l.nameEnglish));
    file.writeln();

    file.writeln(IoLine.Hash(glo.levelIntendedNumberOfPlayers,
                                    l.intendedNumberOfPlayers));
    file.writeln(IoLine.Hash(glo.levelSizeX, l.topology.xl));
    file.writeln(IoLine.Hash(glo.levelSizeY, l.topology.yl));
    if (l.topology.torusX || l.topology.torusY) {
        file.writeln(IoLine.Hash(glo.levelTorusX, l.topology.torusX));
        file.writeln(IoLine.Hash(glo.levelTorusY, l.topology.torusY));
    }
    if (l.bgColor != color.black) {
        ubyte r, g, b;
        al_unmap_rgb(l.bgColor, &r, &g, &b);
        file.writeln(IoLine.Hash(glo.levelBackgroundRed,   r));
        file.writeln(IoLine.Hash(glo.levelBackgroundGreen, g));
        file.writeln(IoLine.Hash(glo.levelBackgroundBlue,  b));
    }

    file.writeln();
    if (l.intendedNumberOfPlayers > 1 && l.overtimeSeconds != 0)
        file.writeln(IoLine.Hash(glo.levelSeconds, l.overtimeSeconds));
    file.writeln(IoLine.Hash(glo.levelInitial,  l.initial ));
    if (l.intendedNumberOfPlayers <= 1)
        file.writeln(IoLine.Hash(glo.levelRequired, l.required));
    file.writeln(IoLine.Hash(glo.levelSpawnint, l.spawnint));

    file.writeln();
    foreach (Ac sk, const int nr; l.skills.byKeyValue)
        if (nr != 0)
            file.writeln(IoLine.Hash(acToString(sk), nr));
    // Always write at least ex- or imploder, to determine ploder in panel.
    if (l.skills[Ac.imploder] == 0 && l.skills[Ac.exploder] == 0)
        file.writeln(IoLine.Hash(l.ploder.acToString, 0));

    // I assume that gadgets have no dependencies and generate valid IoLines
    // all by themselves. Write all gadget vectors to file.
    foreach (vec; l.gadgets) {
        if (vec != null)
            file.writeln();
        vec.map!(occ => occ.toIoLine).each!(line => file.writeln(line));
    }

    if (l.terrain != null)
        file.writeln();
    const(TileGroup)[] writtenGroups;
    const nameSource = TilegroupNameSource.fromDate(l.built);

    foreach (ref const(TerOcc) occ; l.terrain) {
        file.writeDependencies(occ.tile, &writtenGroups, nameSource);
        auto line = groupOrRegularTileLine(occ, writtenGroups, nameSource);
        assert (line);
        file.writeln(line);
    }
}



///////////////////////////////////////////////////////////////////////////////
private: ///////////////////////////////////////////////////////////// :private
///////////////////////////////////////////////////////////////////////////////

struct TilegroupNameSource {
    string builtAsString;

    public static typeof(this) fromDate(Date d)
    {
        import std.ascii;
        import std.array;
        import std.exception;

        typeof(this) ret;
        ret.builtAsString = d.toString
            .map!(function char(dchar c) { return c & 0xFF; })
            .filter!isDigit.array.assumeUnique;
        return ret;
    }
}

// Returns null if we can't resolve the occurrence back to key.
// Returns an IoLine with non-null text1 otherwise.
private IoLine groupOrRegularTileLine(
    in TerOcc occ,
    in const(TileGroup)[] writtenGroups,
    /*
     * nameSource: This is a dumb hack. The writtenGroups should really
     * remember their names. In this hack, instead, we abuse our knowledge
     * that the names are (string const per save) + "-" + running count.
     */
    in TilegroupNameSource nameSource
)
out (ret) {
    assert (ret is null || ret.text1 != null);
}
do {
    auto ret = occ.toIoLine();
    if (ret.text1 == null) {
        auto id = writtenGroups.countUntil(occ.tile);
        if (id >= 0) {
            /*
             * Here, we duplicate the knowledge that the names are
             * (const per save) + "-" + running count.
             */
            ret.text1 = "%s%s-%d".format(glo.levelUseGroup,
                nameSource.builtAsString, id);
        }
    }
    return (ret.text1 != null) ? ret : null;
}

private void writeDependencies(
    std.stdio.File file,
    in AbstractTile tile,
    const(TileGroup)[]* written,
    const(TilegroupNameSource) nameSource
) {
    if (canFind(*written, tile))
        return;
    // Recursive traversal of the dependencies
    foreach (dep; tile.dependencies)
        if (! canFind(*written, dep))
            file.writeDependencies(dep, written, nameSource);
    assert (tile.dependencies.all!(dep => canFind(*written, dep)
        || dep.dependencies.empty), "I don't write non-groups (that have no "
        ~ "dependencies) to the list, but everything else should be there.");
    // The workload of this recursive function
    if (! canFind(*written, tile)
        && tile.dependencies.length != 0 // This is a group, can be dependency.
    ) {
        auto group = cast (const(TileGroup)) tile;
        assert (group);
        assert (! group.dependencies.canFind(group));
        scope (exit)
            *written ~= group;
        file.writeln(IoLine.Dollar(glo.levelBeginGroup,
                    createNameForThisGroup(*written, nameSource)));
        scope (exit)
            file.writeln(IoLine.Dollar(glo.levelEndGroup, ""));
        foreach (elem; group.key.elements) {
            auto line = groupOrRegularTileLine(elem, *written, nameSource);
            assert (line, "We should only write groups when all elements "
                ~ "are either already-written groups or plain tiles!");
            file.writeln(line);
        }
    }
}

private string createNameForThisGroup(
    const(TileGroup[]) writtenBeforeThis,
    const(TilegroupNameSource) nameSource,
) {
    return nameSource.builtAsString
        ~ "-"
        ~ writtenBeforeThis.length.to!string;
}
