module file.key.key;

/*
 * A key is either
 *      the ID of a keyboard key,
 *      the ID of a mouse button,
 *      or a mouse wheel direction.
 *
 * See hardware.keyset.KeySet for the struct that you really bind to functions
 * in the options menu. A KeySet contains zero or more Keys.
 */

struct Key {
private:
    /*
     * A = 1, B = 2, ..., this runs through all Allegro-mapped keyboard keys.
     */
    int _kb;

    /*
     * 1 = LMB, 2 = RMB, 3 = some third button, ...
     * -1 = Wheel up
     * -2 = Wheel down
     */
    int _mb;

public:
    static Key allegroKeyId(in int a5KeyId) pure nothrow @safe @nogc
    {
        return Key(a5KeyId, 0);
    }

    static Key mouseButtonId(in int mButtonId) pure nothrow @safe @nogc
    {
        return Key(0, mButtonId);
    }

    enum Key lmb = Key(0, 1);
    enum Key rmb = Key(0, 2);
    enum Key mmb = Key(0, 3);
    enum Key wheelUp = Key(0, -1);
    enum Key wheelDown = Key(0, -2);

    bool isValid() const pure nothrow @safe @nogc
    {
        return (_kb != 0) ^ (_mb != 0);
    }

    enum Type {
        keyboardKey,
        mouseButton,
        mouseWheelDirection,
    }

    Type type() const pure nothrow @safe @nogc
    {
        return _mb > 0 ? Type.mouseButton
            :  _mb < 0 ? Type.mouseWheelDirection : Type.keyboardKey;
    }

    int opCmp(in typeof(this) rhs) const pure nothrow @safe @nogc
    {
        return _kb != rhs._kb ? _kb - rhs._kb
                              : _mb - rhs._mb;
    }

    int keyboardKey() const pure nothrow @safe @nogc
    in { assert (type == Type.keyboardKey, "It's not a keyboard key"); }
    do { return _kb; }

    int mouseButton() const pure nothrow @safe @nogc
    in { assert (type == Type.mouseButton, "It's not a mouse button"); }
    do { return _mb; }

    bool isWheelUp() const pure nothrow @safe @nogc
    {
        return this == Key.wheelUp;
    }

    bool isWheelDown() const pure nothrow @safe @nogc
    {
        return this == Key.wheelDown;
    }

private:
    this(int a, int b) pure nothrow @safe @nogc
    {
        _kb = a;
        _mb = b;
    }
}
