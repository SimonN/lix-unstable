module graphic.gadget.openfor;

/*
 * GadgetAnimsOnFeed allows for two different rows of animation: The first row
 * is looped while idle. When a lix enters, the game immediately jumps to the
 * second row, finishes one loop through the second row, then displays the
 * first frame of the first row again. This first frame of the first row is
 * skipped if the gadget is triggered immediately again that frame, instead
 * looping back to the beginning of the second row. Thus: If the second row
 * has n frames, the gadget activates every n frames.
 *
 * Second row doesn't exist: This is outdated from C++ Lix and D Lix 0.6.
 * I removed the code for that. It worked like this: Frame 0 from the first
 * row is shown all the time while idle. All frames other than the first frame
 * act like the second row in the second-row-exists case. You had to loop
 * into frame 0 and show frame 0 at least once between two eatings.
 */

import basics.styleset;
import basics.topology;
import graphic.gadget;
import tile.occur;
import net.repdata;
import physics.effect;

public alias Muncher  = GadgetAnimsOnFeed;
public alias Catapult = GadgetAnimsOnFeed; // see gadget.d for FlingPerm

private class GadgetAnimsOnFeed : Gadget {
private:
    Phyu _lastFed;
    StyleSet _lastDish;
    immutable int _idleAnimLen;
    immutable int _eatingAnimLen;

public:
    this(const(Topology) top, in GadOcc levelpos)
    out { assert (_idleAnimLen >= 1); }
    do {
        super(top, levelpos);
        _idleAnimLen = delegate() {
            if (! tile || ! tile.cb || ! tile.cb.frameExists(0, 0))
                return 1;
            for (int i = 0; i < tile.cb.xfs; ++i)
                if (! tile.cb.frameExists(i, 0))
                    return i;
            return tile.cb.xfs;
        }();
        _eatingAnimLen = delegate() {
            if (! tile || ! tile.cb)
                return 1;
            else if (tile.cb.yfs == 1)
                return tile.cb.xfs - 1; // only for physics compatibility
            else for (int i = 0; i < tile.cb.xfs; ++i)
                if (! tile.cb.frameExists(i, 1))
                    return i;
            return tile.cb.xfs;
        }();
    }

    this(in GadgetAnimsOnFeed rhs)
    {
        super(rhs);
        _lastFed = rhs._lastFed;
        _idleAnimLen = rhs._idleAnimLen;
        _eatingAnimLen = rhs._eatingAnimLen;
    }

    override GadgetAnimsOnFeed clone() const
    {
        return new GadgetAnimsOnFeed(this);
    }

    bool isOpenFor(in Phyu upd, in Style st) const
    {
        // During a single update, the gadget can eat a lix from each tribe.
        // This is fairest in multiplayer.
        if (_lastFed == upd)
            return ! _lastDish.contains(st);
        else
            return ! isEating(upd);
    }

    bool isEating(in Phyu upd) const pure nothrow @safe @nogc
    {
        assert (upd >= _lastFed, "relics from the future");
        return upd < firstIdlingPhyuAfterEating;
    }

    void feed(in Phyu upd, in Style st)
    {
        assert (isOpenFor(upd, st), "don't feed what it's not open for");
        assert (upd >= _lastFed, "Gadget ate in the future? Bad savestating.");
        if (upd > _lastFed) {
            _lastFed = upd;
            _lastDish.clear;
        }
        _lastDish.insert(st);
    }

protected:
    override Gadget.Frame frame(in Phyu now) const pure nothrow @safe @nogc
    {
        return isEating(now)
            ? Gadget.Frame(now - _lastFed, true)
            : Gadget.Frame((now - firstIdlingPhyuAfterEating) % _idleAnimLen,
                false);
    }

private:
    Phyu firstIdlingPhyuAfterEating() const pure nothrow @safe @nogc
    {
        return _lastFed == 0 ? Phyu(0) // never eaten anything
            : Phyu(_lastFed + _eatingAnimLen);
    }
}
