module file.option.useropt;

/* This expresses a single global option settable by the user. This option
 * will be saved into the user file, not the all-user global config file.
 *
 * For the collection of all user options, including the methods to save/load
 * them all at once to/from the user file see module file.option.allopts.
 *
 * Contract with file.language.Lang:
 * Each short option description (caption in the options menu)
 * is immediately followed in Lang by the long description, for the option bar.
 */

import std.algorithm;
import std.array;
import std.conv;
import std.string;

import file.filename;
import file.language;
import file.key.key;
import file.key.set;
import file.sdlang;
import hardware.keyboard; // Convenience: Call wasTapped directly on the option

abstract class AbstractUserOption {
private:
    immutable string _userFileKey;
    immutable Lang _lang; // translatable name for the options dialog

public:
    this(string aKey, Lang aLang)
    {
        _userFileKey = aKey;
        _lang = aLang;
    }

    final Lang lang() const pure nothrow @safe @nogc { return _lang; }

    final void set(in SDLNode tag)
    {
        assert (tag.name == _userFileKey,
            "this.name == '" ~ _userFileKey
            ~ "' != tag.name == '" ~ tag.name ~ "'");
        setImpl(tag);
    }

    final SDLNode createTag() const
    {
        auto ret = SDLNode(_userFileKey);
        this.addValueTo(ret);
        return ret;
    }

protected:
    abstract void setImpl(in SDLNode);
    abstract void revertToDefault();

    // To be called from the base class's createTag().
    // The child class should add their values to the tag, but keep the
    // tag's name as-is.
    abstract void addValueTo(ref SDLNode) const;
}



class UserOptionFilename : AbstractUserOption {
private:
    Filename _defaultValue;
    MutFilename _value;

public:
    this(string aKey, Lang aShort, Filename aValue)
    {
        super(aKey, aShort);
        _defaultValue = aValue;
        _value        = aValue;
    }

    nothrow @nogc @safe {
        Filename defaultValue() const { return _defaultValue; }
        Filename value()        const { return _value; }
        Filename opAssign(Filename aValue)
        {
            _value = aValue;
            return _value;
        }
    }

protected:
    override void setImpl(in SDLNode tag)
    {
        _value = MutFilename(new VfsFilename(tag.spullString));
    }

    override void addValueTo(ref SDLNode tag) const
    {
        tag.values ~= SDLValue(_value.rootless);
    }

    override void revertToDefault() { _value = _defaultValue; }
}



class UserOption(T) : AbstractUserOption
    if (is (T == int) || is (T == bool) || is (T == string) || is (T == KeySet)
) {
private:
    immutable T _defaultValue;
    T _value;

public:
    this(string aKey, Lang aShort, T aValue)
    {
        super(aKey, aShort);
        _defaultValue = aValue;
        _value        = aValue;
    }

    nothrow @nogc @safe {
        T defaultValue() const { return _defaultValue; }
        T value()        const { return _value; }
        T opAssign(const(T) aValue) { return _value = aValue; }
    }

    static if (is (T == KeySet)) {
        const nothrow @safe @nogc:
        bool wasTapped() { return _value.wasTapped; }
        bool isHeld() { return _value.isHeld; }
        bool wasReleased() { return _value.wasReleased; }
        bool wasTappedOrRepeated() { return _value.wasTappedOrRepeated; }
    }

protected:
    override void setImpl(in SDLNode tag)
    {
        static if (is (T == KeySet)) {
            _value = KeySet();
            foreach (ref value; tag.spullAllInts) {
                const Key k = old2024IntToKey(spullInt(value));
                _value = KeySet(_value, KeySet(k));
            }
            foreach (ref attr; tag.attributes) {
                const Key k = attributeToKey(attr); // Key.init
                _value = KeySet(_value, KeySet(k));
            }
            return;
        }
        /*
         * Set _value to the first (and, with hope, only) tag.
         * If the tag's value type-mismatches, _value = 0 or = "".
         */
        if (tag.values.length == 0) {
            return;
        }
        static      if (is (T == int)) { _value = tag.spullInt; }
        else static if (is (T == bool)) { _value = tag.spullBool; }
        else static if (is (T == string)) { _value = tag.spullString; }
        else static assert (is (T == KeySet), "All other T need impl here.");
    }

    override void addValueTo(ref SDLNode tag) const
    {
        static if (is (T == int) || is (T == bool) || is (T == string)) {
            tag.values ~= SDLValue(value);
        }
        else static if (is (T == KeySet)) {
            foreach (Key keyToExport; _value[]) {
                tag.add2025(keyToExport);
                tag.maybeAdd2024BackCompat(keyToExport);
            }
        }
        else
            static assert (false);
    }

    override void revertToDefault() { _value = _defaultValue; }
}

private:

// Keywords for import/export of options.
enum kwMButton = "mouseButton";
enum kwWheel = "mouseWheel";
enum kwWhUp = "up";
enum kwWhDown = "down";

// Remove this in 2028, and remove all usages here then.
enum old2024AllegroKeyMax = 227;

/*
 * In 2028, replace calls to old2024IntToKey with calls to Key.byA5KeyId.
 */
Key old2024IntToKey(in int from2024) pure nothrow @safe @nogc
{
    return from2024 == old2024AllegroKeyMax ? Key.mmb
        : from2024 == old2024AllegroKeyMax + 1 ? Key.rmb
        : from2024 == old2024AllegroKeyMax + 2 ? Key.wheelUp
        : from2024 == old2024AllegroKeyMax + 3 ? Key.wheelDown
        : Key.byA5KeyId(from2024);
    // KeySet is responsible for discarding invalid Keys that we produce here.
}

Key attributeToKey(in SDLAttribute attr)
{
    if (attr.name == kwMButton && attr.value.canSpullInt) {
        immutable k = Key.byMouseButtonId(attr.value.spullInt);
        // Don't allow LMB, it's not mappable in the options menu either.
        return k != Key.lmb ? k : Key.init;
    }
    if (attr.name == kwWheel && attr.value.canSpullString) {
        return attr.value.spullString == kwWhUp ? Key.wheelUp : Key.wheelDown;
    }
    return Key.init;
}

void add2025(ref SDLNode target, in Key keyToExport)
{
    final switch (keyToExport.type) {
    case Key.Type.keyboardKey:
        target.values ~= SDLValue(keyToExport.keyboardKey);
        return;
    case Key.Type.mouseButton:
        target.attributes ~= SDLAttribute(kwMButton,
            SDLValue(keyToExport.mouseButton));
        return;
    case Key.Type.mouseWheelDirection:
        target.attributes ~= SDLAttribute(kwWheel,
            SDLValue(keyToExport == Key.wheelUp ? kwWhUp : kwWhDown));
        return;
    }
}

void maybeAdd2024BackCompat(ref SDLNode target, in Key keyToExport)
{
    int backCompat
        = keyToExport == Key.mmb ? old2024AllegroKeyMax
        : keyToExport == Key.rmb ? old2024AllegroKeyMax + 1
        : keyToExport == Key.wheelUp ? old2024AllegroKeyMax + 2
        : keyToExport == Key.wheelDown ? old2024AllegroKeyMax + 3
        : 0;
    if (backCompat == 0) {
        return;
    }
    target.values ~= SDLValue(backCompat);
}

unittest
{
    UserOption!int a = new UserOption!int("myUnittestKey", Lang.commonOk, 4);
    a = 5;
    assert (a.createTag().name == "myUnittestKey");
    assert (a.createTag().values[0].spullInt == 5);
}

unittest {
    UserOption!KeySet mykey = new UserOption!KeySet("myHotkeyKey",
        Lang.optionKeyMenuOkay, KeySet(Key.byA5KeyId(45)));
    assert (mykey.createTag().name == "myHotkeyKey");
    assert (mykey.createTag().values[0].spullInt == 45);

    sdlite.parseSDLDocument!(node => mykey.set(node))(
        "myHotkeyKey 2 1 4 3 2 2 2\n",
        "unittest1");
    assert (mykey.createTag().values.equal([
        SDLValue(1), SDLValue(2), SDLValue(3), SDLValue(4)]));

    mykey = KeySet();
    assert (mykey.createTag().values.empty);
    mykey.set(SDLNode("myHotkeyKey", []));
    assert (mykey.createTag().values.empty);
}

unittest {
    UserOption!KeySet ourOpt = new UserOption!KeySet("myMouseButtonOption",
        Lang.optionKeyMenuOkay, KeySet(Key.byMouseButtonId(7)));
    assert (ourOpt.createTag().values.empty);
    assert (ourOpt.createTag().attributes.length == 1);
    {
        auto attr = ourOpt.createTag().attributes.front;
        assert (attr.name == "mouseButton");
        assert (attr.value.spullInt == 7);
    }
    sdlite.parseSDLDocument!(node => ourOpt.set(node))(
        "myMouseButtonOption mouseButton=10 mouseButton=9\n",
        "unittest2");
    assert (ourOpt.value == KeySet(
        KeySet(Key.byMouseButtonId(9)), KeySet(Key.byMouseButtonId(10))));
}

unittest {
    UserOption!KeySet ourOpt = new UserOption!KeySet("myMouseButtonOption",
        Lang.optionKeyMenuOkay, KeySet(Key.rmb));
    assert (ourOpt.createTag().values.length == 1,
        "This is the 2024 fallback: We export MMB, RMB, wheel up/down as"
        ~ " keyboard integers that Lix versions from 2024 can understand."
        ~ " In 2028, require .length == 0 here.");
    auto attrs = ourOpt.createTag().attributes;
    assert (attrs.length == 1);
    assert (attrs[0].name == kwMButton);
    assert (attrs[0].value.spullInt == 2);
}

unittest {
    UserOption!KeySet ourOpt = new UserOption!KeySet("myMouseWheelOption",
        Lang.optionKeyMenuOkay, KeySet(Key.wheelDown));
    assert (ourOpt.createTag().values.length == 1,
        "This is the 2024 fallback: We export MMB, RMB, wheel up/down as"
        ~ " keyboard integers that Lix versions from 2024 can understand."
        ~ " In 2028, require .length == 0 here.");
    auto attrs = ourOpt.createTag().attributes;
    assert (attrs.length == 1);
    assert (attrs[0].name == kwWheel);
    assert (attrs[0].value.spullString == kwWhDown);
}
