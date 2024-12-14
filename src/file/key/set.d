module file.key.set;

/* struct KeySet: An arbitrary set of keys (no duplicates) that can be
 * be merged and queried for presses.
 */

import std.algorithm;
import std.array;
import std.conv;
import std.exception : assumeUnique;

import file.key.key;

struct KeySet {
private:
    immutable(Key)[] _keys;

public:
    this(Key k) pure nothrow @safe
    {
        if (! k.isValid) {
            return;
        }
        _keys = [k];
    }

    this(in int singleAllegroKeyId) pure nothrow @safe
    {
        this(Key.allegroKeyId(singleAllegroKeyId));
    }

    this(const typeof(this)[] sets...) pure
    {
        if (sets.length == 0)
            return;
        else if (sets.length == 1)
            _keys = sets[0]._keys;
        else if (sets.length == 2
            && (sets[0].empty || sets[1].empty)
        ) {
            _keys = sets[0].empty ? sets[1]._keys : sets[0]._keys;
        }
        else {
            Key[] toSort;
            foreach (set; sets)
                toSort ~= set._keys;
            _keys = toSort.sort().uniq.array.assumeUnique;
        }
    }

    bool empty() const pure nothrow @safe @nogc { return _keys.empty; }
    int len() const pure nothrow @safe @nogc
    {
        return _keys.length & 0x7FFF_FFFFu;
    }

    void remove(in Key keyToRm) pure nothrow @safe
    {
        if (_keys.empty || ! keyToRm.isValid) {
            return;
        }
        _keys = _keys.filter!(k => k != keyToRm).array;
    }

    void removeAnySingleOne() pure nothrow @safe @nogc
    {
        if (_keys.empty) {
            return;
        }
        _keys = _keys[0 .. $-1];
    }

    immutable(Key)[] opIndex() const pure nothrow @safe @nogc
    {
        return _keys;
    }

    Key opIndex(in int i) const pure nothrow @safe @nogc
    {
        return _keys[i];
    }
}

unittest {
    KeySet a = KeySet(4);
    KeySet b = KeySet(2);
    KeySet c = KeySet(KeySet(4), KeySet(5), KeySet(3));
    assert (KeySet(a, b, c)._keys == [
        Key.allegroKeyId(2),
        Key.allegroKeyId(3),
        Key.allegroKeyId(4),
        Key.allegroKeyId(5)]);
    c.remove(Key.allegroKeyId(4));
    c.remove(Key.allegroKeyId(6));
    assert (c._keys == [
        Key.allegroKeyId(3),
        Key.allegroKeyId(5)]);
}
