module file.sdlang;

import std.algorithm;
import std.file;

public import sdlite;

import file.filename;
import file.date;

void parseSdlFrom(in Filename fn,
    void function(in ref SDLNode) callbackForEachNode)
{
    immutable string fnRead = fn.stringForReading;
    auto asVoid = std.file.read(fnRead);
    sdlite.parseSDLDocument!callbackForEachNode(
        cast (char[]) asVoid, fnRead);
}

/*
 * spull is a catchy name for "SDLang pull", I made it up for the Lix codebase.
 * It has no meaning elsewhere, and it's ad-hoc. Not a good universal name.
 *
 * spull returns the value of an SDLNode's values/attributes.
 * You get the value if the node contains a value/attribute
 * (the first attribute found by name) with a value of the wanted type.
 * Otherwise, it returns a default (0, empty string, ...).
 */
bool canSpullString(in SDLValue val) => val.kind == val.Kind.text;

string spullString(in SDLValue src)
{
    return src.canSpullString ? src.textValue : "";
}

string spullString(in ref SDLNode src)
{
    return src.values.length == 0 ? "" : src.values[0].spullString;
}

string spullString(in ref SDLNode src, in string wantedAttrName)
{
    auto found = src.attributes.find!(attr
        => attr.name == wantedAttrName && attr.value.canSpullString);
    return found.length == 0 ? "" : found[0].value.textValue;
}

bool canSpullInt(in SDLValue val)
{
    return val.kind == val.Kind.int_ || val.kind == val.Kind.long_;
}

int spullInt(in SDLValue val)
{
    if (val.kind == val.Kind.int_) {
        return val.int_Value;
    }
    if (val.kind == val.Kind.long_) {
        immutable long x = val.long_Value;
        return x >= 0 ? (x & 0x7FFF_FFFF) : -((-x) & 0x7FFF_FFFF);
    }
    return 0;
}

int spullInt(in ref SDLNode src)
{
    return src.values.length == 0 ? 0 : spullInt(src.values[0]);
}

int spullInt(in ref SDLNode src, in string wantedAttrName)
{
    auto found = src.attributes.find!(attr
        => attr.name == wantedAttrName
        && canSpullInt(attr.value));
    return found.length == 0 ? 0 : spullInt(found[0].value);
}

auto spullAllInts(in ref SDLNode src)
{
    return src.values.filter!canSpullInt;
}

bool canSpullBool(in SDLValue val)
{
    return val.kind == val.Kind.bool_;
}

bool spullBool(in ref SDLNode src)
{
    return src.values.length > 0
        && src.values[0].canSpullBool
        && src.values[0].bool_Value;
}
