module file.trophy.case_;

/*
 * TrophyCase: Caches trophies, loads/saves them.
 */

import std.algorithm;
import std.file;
import std.string;

import optional;

import basics.globals;
import file.date;
import file.backup;
import file.log;
import file.sdlang;
import file.trophy.trophy;
import hardware.tharsis;

private Trophy[TrophyKey] _trophies;

void deleteAllTrophies()
{
    _trophies = null;
}

/*
 * maybeImprove: Update trophy database (user progress, list of checkmarks)
 * with a new level result. This tries to save the best result per level.
 * Call this only with winning _trophies! The progress database doesn't know
 * whether a result is winning, it merely knows how many lix were saved.
 *
 * Returns true if we updated the previous result or if no previous result
 * existed. Returns false if the previous result was already equal or better.
 */
bool maybeImprove(in TrophyKey key, in Trophy tro)
in {
    assert (tro.built !is null, "don't save trophies without a built Date");
}
do {
    if (key.fileNoExt == "")
        return false;
    Trophy* old = key in _trophies;
    if (! old) {
        old = legacyKeyFor(key) in _trophies;
    }
    if (! old || tro.shouldReplaceAfterPlay(*old)) {
        _trophies.remove(legacyKeyFor(key));
        _trophies[key] = tro;
        return true;
    }
    else {
        return false;
    }
}

Optional!Trophy getTrophy(in TrophyKey key)
{
    if (Trophy* ret = key in _trophies)
        return some(*ret);
    else if (Trophy* ret = legacyKeyFor(key) in _trophies)
        return some(*ret);
    else
        return no!Trophy;
}

void loadTrophies()
{
    _trophies = null;
    try {
        version (tharsisprofiling)
            auto zone = Zone(profiler, "load trophies as SDLang");
        parseSdlFrom(fileTrophies, &addSdlTrophy);
    }
    catch (FileException e) {
        log("Can't open trophy file: " ~ fileTrophies.rootless);
        log("    -> " ~ e.msg.replace(": Bad address", "File doesn't exist."));
        log("    -> This is normal on first run. Starting with no trophies.");
    }
    catch (Exception e) {
        log("Syntax errors in trophy file: " ~ fileTrophies.rootless);
        log("    -> " ~ e.msg);
        backupBrokenSdlang(fileTrophies, e);
    }
}

void saveTrophies()
{
    version (tharsisprofiling)
        auto zone = Zone(profiler, "save trophies as SDLang");

    auto f = fileTrophies.openForWriting;
    auto outputRangeToTrophyFile = f.lockingTextWriter;
    auto node = SDLNode(tagName, [], [
        SDLAttribute(attrFileNoExt, SDLValue("")),
        SDLAttribute(attrTitle, SDLValue("")),
        SDLAttribute(attrAuthor, SDLValue("")),
        SDLAttribute(attrLixSaved, SDLValue(0)),
        SDLAttribute(attrSkillsUsed, SDLValue(0)),
        SDLAttribute(attrBuilt, SDLValue("")),
        SDLAttribute(attrLastDir, SDLValue("")) ]);
    foreach (key, tro; _trophies) {
        assert (tro.built !is null, "null built for " ~ key.fileNoExt);
        node.attributes[0].value = key.fileNoExt;
        node.attributes[1].value = key.title;
        node.attributes[2].value = key.author;
        node.attributes[3].value = tro.lixSaved;
        node.attributes[4].value = tro.skillsUsed;
        node.attributes[5].value = tro.built.toString;
        node.attributes[6].value = tro.lastDirWithinLevels;
        generateSDLang(outputRangeToTrophyFile, node);
    }
    f.close();
}

///////////////////////////////////////////////////////////////////////////////

private:

enum tagName = "trophy";
enum attrFileNoExt = "file";
enum attrTitle = "title";
enum attrAuthor = "author";
enum attrLixSaved = "lixSaved";
enum attrSkillsUsed = "skillsUsed";
enum attrBuilt = "built";
enum attrLastDir = "lastDir"; // saved without leading "levels/"

TrophyKey legacyKeyFor(in TrophyKey normalKey) pure @nogc nothrow
{
    TrophyKey ret;
    ret.fileNoExt = normalKey.fileNoExt;
    ret.title = "";
    ret.author = "";
    return ret;
}

void addDuringLoad(in TrophyKey key, in Trophy tro)
in {
    assert (tro.built !is null, "don't save trophies without a built Date");
}
do {
    // Don't call addTrophy because that always overwrites the date.
    // We want the newest date here to tiebreak, unlike addTrophy.
    Trophy* old = (key in _trophies);
    if (! old || tro.shouldReplaceDuringUserDataLoad(*old))
        _trophies[key] = tro;
}

string fixOutdatedAuthor(in string oldAuthor) pure nothrow @safe @nogc
{
    // To convert trophies older than July 2024. Keep this line until 2029.
    return oldAuthor == "Michael S. Repton" ? "Proxima" : oldAuthor;
}

void addSdlTrophy(in ref SDLNode node) {
    if (node.qualifiedName != tagName) {
        return;
    }
    TrophyKey key;
    key.fileNoExt = node.spullString(attrFileNoExt);
    key.title = node.spullString(attrTitle);
    key.author = node.spullString(attrAuthor).fixOutdatedAuthor;
    if (key.fileNoExt == "")
        return;

    Trophy tro = Trophy(
        new Date(node.spullString(attrBuilt)), // = Date("0000-00-00") if n/a
        node.spullString(attrLastDir));
    tro.lixSaved = node.spullInt(attrLixSaved);
    tro.skillsUsed = node.spullInt(attrSkillsUsed);
    if (tro.lixSaved <= 0)
        return;

    addDuringLoad(key, tro);
}
