module physics.state;

/* A gamestate. It saves everything about the current position, but not
 * how we got here. The class Replay saves everything about the history,
 * so you can reconstruct the current state from the beginning gamestate and
 * a replay.
 */

import std.algorithm;
import std.conv;
import std.range;
import std.typecons;

import optional;

import basics.help; // clone(T[]), a deep copy for arrays
import basics.topology;
import graphic.torbit;
import graphic.gadget;
import hardware.tharsis;
import net.repdata;
import net.style;
import physics.tribe;
import physics.nuking;
import tile.phymap;

alias GameState = RefCounted!(RawGameState, RefCountedAutoInitialize.no);

GameState clone(in GameState gs)
{
    GameState ret;
    ret.refCountedStore.ensureInitialized();
    ret.refCountedPayload = gs.refCountedPayload;
    return ret;
}

private struct RawGameState {
public:
    Phyu update;
    int overtimeAtStartInPhyus;

    /*
     * In 0.9 and older, we computed goalsAreOpen from the tribes' nukes states
     * just-in-time, which led to the Red Will Win bug where the red player
     * would score, then all goals would immediately close before other tribes'
     * lix would be able to exit during the same phyu.
     *
     * In 0.10, we computed it once at the start of the model's advance()
     * and passed it around. It really behaves like a global w.r.t. physics.
     *
     * From 0.11 on, we're honest enough to just make it a public bool.
     * Only advance() should toggle it.
     */
    bool goalsAreOpen = true;

    Tribe[Style] tribes; // update order is garden, red, orange, yellow, ...

    Hatch[] hatches;
    Goal[] goals;
    Water[] waters;
    TrapTrig[] traps;
    FlingPerm[] flingPerms;
    FlingTrig[] flingTrigs;

    Torbit land;
    Phymap lookup;

    this(this) { opAssignImpl(this); }

    ref RawGameState opAssign(ref const(RawGameState) rhs) return
    {
        if (this is rhs)
            return this;
        return opAssignImpl(rhs);
    }

    ~this()
    {
        update = Phyu(0);
        if (land) {
            land.dispose();
            land = null;
        }
        lookup = null;
    }

    // With dmd 2.0715.1, inout doesn't seem to work for this.
    // Let's duplicate the function, once for const, once for mutable.
    void foreachConstGadget(void delegate(const(Gadget)) func) const
    {
        chain(hatches, goals, waters, traps, flingPerms, flingTrigs).each!func;
    }
    void foreachGadget(void delegate(Gadget) func)
    {
        chain(hatches, goals, waters, traps, flingPerms, flingTrigs).each!func;
    }

    const pure nothrow @safe @nogc {
        int numTribes() { return tribes.length & 0xFFFF; }

        bool multiplayer()
        in { assert (numTribes > 0); }
        do { return numTribes > 1; }

        Style singleplayerStyle()
        in { assert (! multiplayer); }
        do { return tribes.byKey.front; }

        bool singleplayerHasSavedAtLeast(in int lixRequired)
        {
            return ! multiplayer
                && tribes.byValue.front.score.lixSaved >= lixRequired;
        }

        bool singleplayerHasNuked() const @nogc
        {
            return ! multiplayer && tribes.byValue.front.hasNuked;
        }

        Nuking nuking()
        {
            Nuking ret;
            ret.overtimeAtStartInPhyus = overtimeAtStartInPhyus;
            ret.allAgreedToAbortAt
                = tribes.byValue.any!(tr => ! tr.wantsToAbort) ? no!Phyu
                : tribes.byValue.map!(tr => tr.wantsToAbortAt).optmax;
            ret.overtimeTriggeredAt
                = tribes.byValue.map!(tr => tr.triggersOvertimeAt).optmin;
            ret.overtimeRemainingInPhyus
                = ret.allAgreedToAbort ? 0
                : ! ret.overtimeTriggered ? ret.overtimeAtStartInPhyus
                : clamp(ret.overtimeAtStartInPhyus
                    + ret.overtimeTriggeredAt.front
                    - update, 0, overtimeAtStartInPhyus);
            return ret;
        }
    }

private:
    ref RawGameState opAssignImpl(ref const(RawGameState) rhs) return
    {
        copyValuesArraysFrom(rhs);
        copyLandFrom(rhs);
        lookup = rhs.lookup ? rhs.lookup.clone() : null;
        return this;
    }

    void copyLandFrom(ref const(RawGameState) rhs)
    {
        if (land && land.matches(rhs.land)) {
            land.copyFrom(rhs.land);
        }
        else {
            if (land)
                land.dispose();
            land = rhs.land ? rhs.land.clone() : null;
        }
    }

    void copyValuesArraysFrom(ref const(RawGameState) rhs)
    {
        overtimeAtStartInPhyus = rhs.overtimeAtStartInPhyus;
        update   = rhs.update;
        goalsAreOpen = rhs.goalsAreOpen;
        hatches  = basics.help.clone(rhs.hatches);
        goals    = basics.help.clone(rhs.goals);
        waters   = basics.help.clone(rhs.waters);
        traps    = basics.help.clone(rhs.traps);
        flingPerms = basics.help.clone(rhs.flingPerms);
        flingTrigs = basics.help.clone(rhs.flingTrigs);

        // Deep-clone this by hand, I haven't written a generic clone for AAs
        // Don't start with (tribes = null;) because rhs could be this.
        typeof(tribes) temp;
        foreach (style, tribe; rhs.tribes)
            temp[style] = tribe.clone();
        tribes = temp;
    }
}
