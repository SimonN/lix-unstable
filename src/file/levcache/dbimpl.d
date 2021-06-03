module file.levcache.dbimpl;

private:

struct Payload {
    int weight; // See Rhino for what weight means.
    int numCompleted;
}

class LevelCache

class RhinoThatPointsToDB : Rhino {
private:
    LevelCache _db;
    Filename _fn;

private: // of this module
    this(LevelCache db, Filename fn)
    {
        _db = db;
        _fn = fn;
    }

public:
    const pure nothrow @safe @nogc {
        Filename filename() { return _fn; }
        int weight() { return _db.rawCache[_fn].weight; }
        int numCompleted() { return _db.rawCache[_fn].numCompleted; }
    }

    void recacheOnlyThis()
    {
        _db.recacheOnly(_fn);
    }


}
