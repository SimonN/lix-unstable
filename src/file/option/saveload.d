module file.option.saveload;

import std.file;
import std.string;

import basics.globals;
import file.backup;
import file.option.allopts;
import file.log;
import file.sdlang;
import hardware.tharsis;

void loadUserOptions()
{
    file.option.allopts.initializeIfNecessary();
    _unknownOptions = null;
    try {
        version (tharsisprofiling)
            auto zone = Zone(profiler, "load options SDLang");
        file.sdlang.parseSdlFrom(fileOptions, &addSdlOption);
    }
    catch (FileException e) {
        log("Can't open options file: " ~ fileOptions.rootless);
        log("    -> " ~ e.msg.replace(": Bad address", "File doesn't exist."));
        log("    -> This is normal on first run. Using default options.");
    }
    catch (Exception e) {
        log("Syntax errors in options file: " ~ fileOptions.rootless);
        log("    -> " ~ e.msg);
        backupBrokenSdlang(fileOptions, e);
    }
}

nothrow void saveUserOptions()
{
    version (tharsisprofiling)
        auto zone = Zone(profiler, "save options SDLang");
    try {
        auto f = fileOptions.openForWriting;
        writeKnownOptionsTo(f);
        writeUnknownOptionsTo(f);
    }
    catch (Exception e) {
        log("Can't save options to: " ~ fileOptions.rootless);
        log("    -> " ~ e.msg);
    }
}

///////////////////////////////////////////////////////////////////////////////

private:

/*
 * Before Lix 0.10.22, when you played Lix version B, then play A < B,
 * then play B again, version A saved only the options that A knew and
 * failed to save those that were new in B. Now, if we're in version A,
 * _unknownOptions will track what's new in B.
 */
const(SDLNode)[] _unknownOptions = null;

void addSdlOption(in ref SDLNode node)
{
    if (auto opt = node.name in _optvecLoad) {
        opt.set(node);
    }
    else {
        _unknownOptions ~= node;
    }
}

// Can throw FileException or SDLang's own exceptions.
void writeKnownOptionsTo(ref typeof(fileOptions.openForWriting()) f)
{
    auto o = f.lockingTextWriter;
    foreach (opt; _optvecSave) {
        if (opt is screenType) {
            o.put("// screenMode 0: windowed, user-defined window size\n"
                ~ "// screenMode 1: software fullscreen, automatic resol.\n"
                ~ "// screenMode 2: hardware fullscreen, user-defined resol.\n"
                );
        }
        generateSDLang(o, opt.createTag);
    }
}

// Can throw FileException or SDLang's own exceptions.
void writeUnknownOptionsTo(ref typeof(fileOptions.openForWriting()) f)
{
    if (_unknownOptions.length == 0) {
        return;
    }
    f.writeln();
    f.writeln("// Unknown options from past or future Lix versions");
    auto o = f.lockingTextWriter;
    generateSDLang(o, _unknownOptions);
}
