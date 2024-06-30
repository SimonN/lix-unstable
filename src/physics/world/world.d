module physics.world.world;

/*
 * A World is the gamestate, but without the logic how to update it.
 *
 * A World consists of two halves, the mutable half and the immutable half.
 * PhysicsCache will store deep copies of the mutable half for backtracking.
 *
 * The logic about how to advance the world during a physics update
 * is elsewhere (../model.d) and the history (what to do when) is elsewhere
 * again (class Replay). These two together are responsible to reconstruct
 * the current World from the beginning of play.
 */

import core.stdc.string : memcpy, memset;

import std.algorithm;
import std.conv;
import std.range;

import basics.help; // clone(T[]), a deep copy for arrays
import basics.topology;
import graphic.torbit;
import graphic.gadget;
import hardware.tharsis;
import net.repdata;
import net.style;
import physics.tribe;
import physics.tribes;
import tile.phymap;

alias World = WorldAsStruct*;
alias ConstWorld = const(WorldAsStruct)*;

struct WorldAsStruct {
    ImmutableHalfOfWorld immutableHalf;
    MutableHalfOfWorld mutableHalf;

    private alias mut = mutableHalf;
    private alias immu = immutableHalf;

    mixin(mkDecl("Phyu", "age"));
    mixin(mkDecl("int", "overtimeAtStartInPhyus"));

    mixin(mkDecl("Torbit", "land"));
    mixin(mkDecl("Phymap", "lookup"));
    mixin(mkDecl("Tribes", "tribes"));

    mixin(mkDecl("Hatch[]", "hatches"));
    mixin(mkDecl("Goal[]", "goals"));
    mixin(mkDecl("Water[]", "waters"));
    mixin(mkDecl("TrapTrig[]", "traps"));
    mixin(mkDecl("FlingPerm[]", "flingPerms"));
    mixin(mkDecl("FlingTrig[]", "flingTrigs"));

    void takeOwnershipOf(ref MutableHalfOfWorld wo)
    {
        mut.takeOwnershipOf(wo);
    }

    void dispose() nothrow @nogc
    {
        mut.dispose();
    }

    bool isValid() const pure nothrow @safe @nogc { return mut.isValid; }

    // With dmd 2.0715.1, inout doesn't seem to work for this.
    // Let's duplicate the function, once for const, once for mutable.
    void foreachConstGadget(void delegate(const(Gadget)) func) const
    {
        chain(mut.hatches, mut.goals, mut.waters, mut.traps,
            mut.flingPerms, mut.flingTrigs
            ).each!func;
    }
    void foreachGadget(void delegate(Gadget) func)
    {
        chain(mut.hatches, mut.goals, mut.waters, mut.traps,
            mut.flingPerms, mut.flingTrigs
            ).each!func;
    }

    const pure nothrow @safe @nogc {
        bool isPuzzle() { return mut.tribes.isPuzzle; }
        bool isBattle() { return mut.tribes.isBattle; }
        bool isSolvedPuzzle(in int req)
        {
            return mut.tribes.isSolvedPuzzle(req);
        }
    }

    bool someoneDoesntYetPreferGameToEnd() const
    {
        return mut.tribes.playerTribes.any!(tr => ! tr.prefersGameToEnd);
    }

    // False as long as overtime hasn't started running yet.
    // True after overtime has started running, or after overtime has run out.
    bool isOvertimeRunning() const pure nothrow @safe @nogc
    in { assert (isBattle || isPuzzle, "Add players to avoid empty truth."); }
    do {
        return mut.tribes.playerTribes.all!(tr => tr.prefersGameToEnd)
            || mut.tribes.playerTribes.any!(tr => tr.triggersOvertime);
    }

    // Call this only if isOvertimeRunning.
    // Use this only for effect handling. For nuking or exit locking,
    // use nukeIsAssigningExploders or lixMayUseGoals.
    Phyu overtimeRunningSince() const
    in {
        assert (isOvertimeRunning);
    }
    do {
        if (mut.tribes.playerTribes.all!(tr => tr.prefersGameToEnd)) {
            return mut.tribes.playerTribes
                .map!(tr => tr.prefersGameToEndSince.front)
                .reduce!max;
        }
        else {
            assert (mut.tribes.playerTribes.any!(tr => tr.triggersOvertime));
            return mut.tribes.playerTribes
                .filter!(tr => tr.triggersOvertime)
                .map!(tr => tr.triggersOvertimeSince.front)
                .reduce!min;
        }
    }

    // Returns as int, not as Phyu. Phyu is a point in time, not a duration.
    int overtimeRemainingInPhyus() const
    {
        if (! isOvertimeRunning)
            return mut.overtimeAtStartInPhyus;
        if (mut.tribes.playerTribes.all!(tr => tr.prefersGameToEnd))
            return 0;
        return clamp(overtimeAtStartInPhyus + overtimeRunningSince - mut.age,
            0, overtimeAtStartInPhyus);
    }

    bool nukeIsAssigningExploders() const
    {
        return isOvertimeRunning() && overtimeRemainingInPhyus == 0;
    }

    // Extra check (other than nukeIsAssigningExploders) for edge case during
    // race maps (overtime 0, i.e., terminate on first scoring):
    // Assume 3 players enter the exit at the same time. Since one
    // player has to be processed first, that player would, without
    // the next comparison, change the nuke status before processing
    // the next player. The nuke prevents lixes from exiting.
    // Solution: In race maps, allow that one update to finish with scoring.
    bool lixMayUseGoals() const
    {
        return ! nukeIsAssigningExploders || overtimeRunningSince == mut.age;
    }

private:
    static string mkDecl(in string type, in string var)
    {
        return "ref inout(" ~ type ~ ") " ~ var
            ~ "() return inout pure nothrow @safe @nogc { return mut."
            ~ var ~ "; }";
    }
}

struct ImmutableHalfOfWorld {}

struct MutableHalfOfWorld {
public:
    Phyu age;
    int overtimeAtStartInPhyus;

    Torbit land;
    Phymap lookup = null;
    Tribes tribes; // update order is garden, red, orange, yellow, ...

    Hatch[] hatches;
    Goal[] goals;
    Water[] waters;
    TrapTrig[] traps;
    FlingPerm[] flingPerms;
    FlingTrig[] flingTrigs;

    typeof(this) clone() const
    out (ret) { assert (ret.isValid == this.isValid); }
    do {
        MutableHalfOfWorld ret;
        ret.copyValuesArraysFrom(this);
        ret.copyLandFrom(this);
        ret.lookup = lookup ? lookup.clone() : null;
        return ret;
    }

    void takeOwnershipOf(ref typeof(this) rhs) nothrow @nogc
    {
        if (rhs is this) {
            return;
        }
        dispose();
        memcpy(&this, &rhs, typeof(this).sizeof);
        memset(&rhs, 0, typeof(this).sizeof);
    }

    void dispose() nothrow @nogc
    out {
        assert (! isValid, "Callers rely on dispose() invalidating us");
        assert (age <= 0, "Callers rely on our small age");
    }
    do {
        if (land) {
            land.dispose();
        }
        this = typeof(this).init;
    }

    bool isValid() const pure nothrow @safe @nogc { return lookup !is null; }

    invariant()
    {
        if (land !is null) {
            assert (lookup !is null, "Graphical mode needs land and lookup");
            assert (land.albit !is null, "Bug in our Torbit handling."
                ~ " If you dispose the land, always set land = null.");
        }
        // If land is null, lookup may be valid (coverage mode) or null.
    }

private:
    void copyLandFrom(ref const(typeof(this)) rhs)
    {
        if (rhs.land is null) {
            if (land is null) {
                return;
            }
            land.dispose();
            land = null;
            return;
        }
        if (land && land.matches(rhs.land)) {
            land.copyFrom(rhs.land);
            return;
        }
        if (land) {
            land.dispose();
        }
        land = rhs.land.clone();
    }

    void copyValuesArraysFrom(ref const(typeof(this)) rhs)
    {
        overtimeAtStartInPhyus = rhs.overtimeAtStartInPhyus;
        age = rhs.age;
        tribes = rhs.tribes.clone();
        hatches  = basics.help.clone(rhs.hatches);
        goals    = basics.help.clone(rhs.goals);
        waters   = basics.help.clone(rhs.waters);
        traps    = basics.help.clone(rhs.traps);
        flingPerms = basics.help.clone(rhs.flingPerms);
        flingTrigs = basics.help.clone(rhs.flingTrigs);
    }
}
