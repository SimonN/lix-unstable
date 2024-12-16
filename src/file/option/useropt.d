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

import sdlang;

import basics.alleg5 : ALLEGRO_KEY_MAX; // Fallback for 2024 option files
import file.filename;
import file.language;
import file.key.key;
import file.key.set;
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

    final void set(Tag tag)
    {
        assert (tag.name == _userFileKey,
            "this.name == '" ~ _userFileKey
            ~ "' != tag.name == '" ~ tag.name ~ "'");
        setImpl(tag);
    }

    final Tag createTag() const
    {
        Tag tag = new Tag(null, _userFileKey);
        this.addValueTo(tag);
        return tag;
    }

protected:
    abstract void setImpl(Tag tag);
    abstract void revertToDefault();

    // To be called from the base class's createTag().
    // The child class should add their values to the tag, but keep the
    // tag's name as-is.
    abstract void addValueTo(Tag) const;
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
    override void setImpl(Tag tag)
    {
        _value = MutFilename(new VfsFilename(tag.getValue!string));
    }

    override void addValueTo(Tag tag) const
    {
        tag.add(Value(_value.rootless));
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
    override void setImpl(Tag tag)
    {
        static if (is (T == KeySet)) {
            _value = KeySet();
            import std.variant;
            foreach (value; tag.values.filter!(v => v.convertsTo!int)) {
                const Key k = old2024IntToKey(value.get!int);
                _value = KeySet(_value, KeySet(k));
            }
        }
        else {
            // If the tag's value type-mismatches, set _value to _value.
            _value = tag.getValue!T(_value);
        }
    }

    override void addValueTo(Tag tag) const
    {
        static if (is (T == int) || is (T == bool) || is (T == string)) {
            tag.add(Value(value));
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

Key old2024IntToKey(in int from2024Options) pure nothrow @safe @nogc
{
    return from2024Options == ALLEGRO_KEY_MAX ? Key.mmb
        : from2024Options == ALLEGRO_KEY_MAX + 1 ? Key.rmb
        : from2024Options == ALLEGRO_KEY_MAX + 2 ? Key.wheelUp
        : from2024Options == ALLEGRO_KEY_MAX + 3 ? Key.wheelDown
        : from2024Options < ALLEGRO_KEY_MAX ? Key.byA5KeyId(from2024Options)
        : Key.init;
}

void add2025(ref Tag target, in Key keyToExport)
{
    final switch (keyToExport.type) {
    case Key.Type.keyboardKey:
        target.add(Value(keyToExport.keyboardKey));
        return;
    case Key.Type.mouseButton:
        // Add 2025 export string here.
        return;
    case Key.Type.mouseWheelDirection:
        // Add 2025 export string here.
        return;
    }
}

void maybeAdd2024BackCompat(ref Tag target, in Key keyToExport)
{
    int backCompat
        = keyToExport == Key.mmb ? ALLEGRO_KEY_MAX
        : keyToExport == Key.rmb ? ALLEGRO_KEY_MAX + 1
        : keyToExport == Key.wheelUp ? ALLEGRO_KEY_MAX + 2
        : keyToExport == Key.wheelDown ? ALLEGRO_KEY_MAX + 3
        : 0;
    if (backCompat == 0) {
        return;
    }
    target.add(Value(backCompat));
}

unittest
{
    UserOption!int a = new UserOption!int("myUnittestKey", Lang.commonOk, 4);
    a = 5;
    assert (a.createTag().name == "myUnittestKey");
    assert (a.createTag().values.front == 5);
}

unittest {
    UserOption!KeySet mykey = new UserOption!KeySet("myHotkeyKey",
        Lang.optionKeyMenuOkay, KeySet(Key.byA5KeyId(45)));
    assert (mykey.createTag().name == "myHotkeyKey");
    assert (mykey.createTag().values.front == 45);
    {
        Tag root = parseSource("myHotkeyKey 2 1 4 3 2 2 2\n");
        mykey.set(root.tags.front);
        import std.algorithm;
        assert (mykey.createTag().values.equal([1, 2, 3, 4]));
    }
    mykey = KeySet();
    assert (mykey.createTag().values.empty);
    mykey.set(new Tag("", "myHotkeyKey"));
    assert (mykey.createTag().values.empty);
}
