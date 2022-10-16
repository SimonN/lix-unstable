module physics.model;

/*
 * Everything from the physics collected in one class, according to MVC.
 *
 * Does not manage the replay. Whenever you want to advance physics, cut off
 * from the replay the correct hunk, and feed it one-by-one to the model.
 *
 * To do automated replay checking, don't use a model directly! Make a nurse,
 * and have her check the replay!
 */

import std.algorithm;
import std.array;
import std.conv;
import std.range;

import basics.help; // len
import net.repdata;
import hardware.tharsis;
import file.replay;
import graphic.gadget;
import graphic.torbit;
import hardware.sound;
import lix;
import physics.effect;
import physics.physdraw;
import physics.state;
import physics.statinit;
import physics.tribe;
import physics.nuking;
import tile.phymap;

class GameModel {
private:
    GameState     _cs;            // owned (current state)
    PhysicsDrawer _physicsDrawer; // owned
    EffectSink _effect; // not owned, never null. May be the NullEffectSink.

public:
    // The replay data comes with player information (PlNr).
    // Physics only work with tribe information (Style).
    // To preserve database normal form, we shouldn't put the Style in the
    // replay's Ply, but still must ask the caller of advance(),
    // which is the Nurse, to associate Ply to Style via this struct.
    struct ColoredData {
        Ply replayData;
        Style style;
        alias replayData this;
    }

    // This remembers the effect manager, but not anything else.
    // We don't own the effect manager.
    this(in GameStateInitCfg cfg, EffectSink ef)
    in { assert (cfg.tribes.length >= 1); }
    do {
        _effect = ef;
        _cs = newZeroState(cfg);
        _physicsDrawer = new PhysicsDrawer(_cs.land, _cs.lookup);
        finalizePhyuAnimateGadgets();
    }

    void dispose()
    {
        if (_physicsDrawer)
            _physicsDrawer.dispose();
        _physicsDrawer = null;
    }

    // Should be accsessible by the Nurse. Shouldn't be accessed straight from
    // the game, but it's the Nurse's task to hide that information.
    @property inout(GameState) cs() inout { return _cs; }

    void takeOwnershipOf(GameState s)
    {
        _cs = s;
        _physicsDrawer.rebind(_cs.land, _cs.lookup);
        finalizePhyuAnimateGadgets();
    }

    void applyChangesToLand() {
        _physicsDrawer.applyChangesToLand(_cs.update);
    }

    void advance(R)(R range)
        if (isInputRange!R && is (ElementType!R : const(ColoredData)))
    {
        ++_cs.update; // Step 1: Bump only the physics update, do nothing else.

        applyNukeInputs(range.save); // Step 2. Affects tribes.
        immutable nuking = _cs.nuking();

        applySkillInputsOrPerformNuke(range, nuking); // Step 3. Affects tribes
        assert (nuking == _cs.nuking()); // but promises at least this.
        performMostPhysics(nuking); // Step 4.
    }

private:

///////////////////////////////////////////////////////////////////////////////
// Step 2 /////////////////////////////////////////////////////////////////////

    enum string wrongUpd = "advance() should ++_cs.update before calling here."
        ~ " Furthermore, the caller of advance() should filter the"
        ~ " ColoredData to give us only what matches his _cs.update() + 1,"
        ~ " which will be == _cs.update() after advance()'s ++_cs.update.";
    /*
     * advance(), Step 2: Apply nuke input to tribes.
     * This affects tribes by setting their hasNuked.
     * Doesn't set the tribes to 0 lix in hatch, step 3 will do that.
     * Doesn't affect the lix in the tribes' lix vectors.
     * This will not yet assign the exploders, that will happen in step 4.
     *
     * After step 2, we must be able to compute GameState.nuking() and its
     * output (so I decree here and will assert at the beginning of step 4)
     * must remain fixed throughout step 3 and the beginning of step 4.
     */
    void applyNukeInputs(R)(R range)
        if (isInputRange!R && is (ElementType!R : const(ColoredData))
    ) {
        foreach (ref const i; range) {
            assert (i.update == _cs.update, wrongUpd);
            if (i.action != RepAc.NUKE) {
                continue;
            }
            auto tribe = i.style in _cs.tribes;
            if (! tribe) {
                return; // Ignore bogus data that can come from anywhere.
            }
            if (tribe.hasNuked) {
                return; // May not nuke twice.
            }
            tribe.recordNukePressedAt(_cs.update);
            _effect.addSound(_cs.update, Passport(i.style, 0), Sound.NUKE);
        }
    }

///////////////////////////////////////////////////////////////////////////////
// Step 3 /////////////////////////////////////////////////////////////////////

    /*
     * advance(), Step 3: Either-or:
     *      Step 3-N: Apply exploder assignments because we're nuking.
     *      Step 3-S: Apply non-nuke input, i.e., skills, to tribes.
     * Either affects tribes and also lix inside the tribes' lix vectors.
     *
     * Game rule: We do not process further input during nuke.
     * A decisive nuke in phyu N (decisive = a nuke input that triggers
     * nukeIsAssigningExploders) prohibits all skill assignments in
     * phyu N, even if those assignments come earlier in (range)
     * within phyu N. Final assignments may be from phyu N-1.
     */
    void applySkillInputsOrPerformNuke(R)(R range, in Nuking nuking)
        if (isInputRange!R && is (ElementType!R : const(ColoredData))
    ) {
        if (nuking.nukeIsAssigningExploders) {
            assignExplodersFromNuke();
            return;
        }
        foreach (ref const cd; range.filter!(cd => cd.isSomeAssignment)) {
            applyAssignment(cd, nuking);
        }
    }

    void assignExplodersFromNuke()
    {
        foreach (tribe; _cs.tribes) {
            tribe.stopSpawningAnyMoreLixBecauseWeAreNuking();
            foreach (int id, lix; tribe.lixvec.enumerate!int) {
                if (! lix.healthy || lix.ploderTimer > 0)
                    continue;
                auto ow = makeGypsyWagon(Passport(tribe.style, id), false);
                lix.assignManually(&ow, Ac.exploder);
                break; // Nuke hits only one lix per tribe, per advance().
            }
        }
    }

    void applyAssignment(in ColoredData i, in Nuking nuking)
    in {
        assert (i.isSomeAssignment, "Caller should filter");
        assert (i.update == _cs.update, wrongUpd);
    }
    do {
        auto tribe = i.style in _cs.tribes;
        if (! tribe) {
            // Ignore bogus data that can come from anywhere
            return;
        }
        if (tribe.hasNuked) {
            // Game rule: After you call for the nuke, you may not assign
            // other things, nuke again, or do whatever we allow in the future.
            return;
        }
        // never assert based on the content in Ply, which may have
        // been a maleficious attack from a third party, carrying a lix ID
        // that is not valid. If bogus data comes, do nothing.
        if (i.toWhichLix < 0 || i.toWhichLix >= tribe.lixlen) {
            return;
        }
        immutable Passport pa = Passport(i.style, i.toWhichLix);
        immutable upd = _cs.update;
        Lixxie lixxie = tribe.lixvec[i.toWhichLix];
        assert (lixxie !is null);
        if (lixxie.priorityForNewAc(i.skill) <= 1
            || ! tribe.canStillUse(i.skill)
            || (lixxie.facingLeft  && i.action == RepAc.ASSIGN_RIGHT)
            || (lixxie.facingRight && i.action == RepAc.ASSIGN_LEFT))
            return;
        // Physics
        ++(tribe.skillsUsed[i.skill]);
        OutsideWorld ow = makeGypsyWagon(pa, nuking.goalsAreOpen);
        lixxie.assignManually(&ow, i.skill);

        _effect.addSound(upd, pa, Sound.ASSIGN);
        _effect.addArrow(upd, pa, lixxie.foot, i.skill);
    }

    /*
     * Step 4: Advance remaining physics. All input has been applied.
     * As many physics aspects as possible should be in this step.
     */
    void performMostPhysics(in Nuking nuking)
    {
        spawnLixxiesFromHatches(nuking);
        updateLixxies(nuking);
        finalizePhyuAnimateGadgets();
        _effect.announceOvertime(nuking);
    }

///////////////////////////////////////////////////////////////////////////////
// Step 4 /////////////////////////////////////////////////////////////////////

    lix.OutsideWorld makeGypsyWagon(
        in Passport pa, in bool goalsAreOpen
    ) pure nothrow @nogc
    {
        return OutsideWorld(_cs, _physicsDrawer, _effect, pa, goalsAreOpen);
    }

    void spawnLixxiesFromHatches(in Nuking nuking)
    {
        foreach (int teamNumber, Tribe tribe; _cs.tribes) {
            if (tribe.phyuOfNextSpawn() != _cs.update) {
                continue;
            }
            // the only interesting part of OutsideWorld right now is the
            // lookupmap inside the current state. Everything else will be
            // passed anew when the lix are updated.
            auto ow = makeGypsyWagon(
                Passport(tribe.style, tribe.lixlen),
                nuking.goalsAreOpen);
            tribe.spawnLixxie(&ow);
        }
    }

    void updateLixxies(in Nuking nuking)
    {
        version (tharsisprofiling)
            Zone zone = Zone(profiler, "PhysSeq updateLixxies()");
        bool anyFlingers = false;

        /* Refactoring idea:
         * Put this sorting into State, and do it only once at the beginning
         * of a game. Encapsulate (Tribe[Style] tribes) and offer methods that
         * provide the mutable tribe, but don't allow to rewrite the array.
         */
        auto sortedTribes = _cs.tribes.byValue.array.sort!"a.style < b.style";

        void foreachLix(void delegate(Tribe, in int, Lixxie) func)
        {
            foreach (tribe; sortedTribes)
                foreach (int lixID, lixxie; tribe.lixvec.enumerate!int)
                    func(tribe, lixID, lixxie);
        }

        void performFlingersUnmarkOthers()
        {
            foreachLix((Tribe tribe, in int lixID, Lixxie lixxie) {
                lixxie.setNoEncountersNoBlockerFlags();
                if (lixxie.ploderTimer != 0) {
                    auto ow = makeGypsyWagon(Passport(tribe.style, lixID),
                        nuking.goalsAreOpen);
                    handlePloderTimer(lixxie, &ow);
                }
                if (lixxie.updateOrder == PhyuOrder.flinger) {
                    lixxie.marked = true;
                    anyFlingers = true;
                    auto ow = makeGypsyWagon(Passport(tribe.style, lixID),
                        nuking.goalsAreOpen);
                    lixxie.perform(&ow);
                }
                else
                    lixxie.marked = false;
            });
        }

        void applyFlinging()
        {
            if (! anyFlingers)
                return;
            foreachLix((Tribe tribe, in int lixID, Lixxie lixxie) {
                auto ow = makeGypsyWagon(Passport(tribe.style, lixID),
                    nuking.goalsAreOpen);
                lixxie.applyFlingXY(&ow);
            });
        }

        void performUnmarked(PhyuOrder uo)
        {
            foreachLix((Tribe tribe, in int lixID, Lixxie lixxie) {
                if (! lixxie.marked && lixxie.updateOrder == uo) {
                    lixxie.marked = true;
                    auto ow = makeGypsyWagon(Passport(tribe.style, lixID),
                        nuking.goalsAreOpen);
                    lixxie.perform(&ow);
                }
            });
        }

        performFlingersUnmarkOthers();
        applyFlinging();
        _physicsDrawer.applyChangesToPhymap();

        performUnmarked(PhyuOrder.blocker);
        performUnmarked(PhyuOrder.remover);
        _physicsDrawer.applyChangesToPhymap();

        performUnmarked(PhyuOrder.adder);
        _physicsDrawer.applyChangesToPhymap();

        performUnmarked(PhyuOrder.peaceful);
    }

    void finalizePhyuAnimateGadgets()
    {
        // Animate after we had the traps eat lixes. Eating a lix sets a flag
        // in the trap to run through the animation, showing the first killing
        // frame after this next perform() call. Physics depend on this anim!
        _cs.foreachGadget((Gadget g) { g.perform(_cs.update, _effect); });
    }
}
