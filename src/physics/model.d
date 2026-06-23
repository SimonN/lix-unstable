module physics.model;

/*
 * GameModel: Applies to the GameState/RawGameState all physics logic that
 * isn't yet part of a single lix, or a single gadget. E.g., in GameModel,
 * we define the order of the many updates during a single physics update.
 *
 * GameModel does not manage the replay. Whenever you want to advance physics,
 * cut off from the replay (that you hold elsewhere, usually in a Nurse) the
 * correct hunk, and feed it one-by-one to the model.
 *
 * For automated replay verification a.k.a. replay checking a.k.a. mass replay
 * verification, don't use a model directly. Make a VerifyingNurse that holds
 * a GameModel and a Replay.
 */

import std.algorithm;
import std.array;
import std.conv;
import std.range;

import basics.help; // len
import hardware.tharsis;
import file.replay;
import physics.gadget;
import graphic.torbit;
import hardware.sound;
import net.name;
import physics.effect;
import physics.lixxie.fields;
import physics.lixxie.fuse;
import physics.lixxie.lixxie;
import physics.physdraw;
import physics.world.world;
import physics.world.init;
import physics.tribe;
import tile.phymap;

class GameModel {
private:
    WorldAsStruct _cs; // owned (current state)
    PhysicsDrawer _physicsDrawer; // owned
    EffectSink _effect; // not owned, never null. May be the NullEffectSink.

public:
    // This remembers the effect manager, but not anything else.
    // We don't own the effect manager.
    this(in GameStateInitCfg cfg, EffectSink ef)
    in { assert (cfg.tribes.length >= 1); }
    do {
        _effect = ef;
        _cs = newZeroState(cfg);
        assert (_cs.isValid);
        _physicsDrawer = new PhysicsDrawer(_cs.land, _cs.lookup);
    }

    // Should be accsessible by the Nurse. Shouldn't be accessed straight from
    // the game, but it's the Nurse's task to hide that information.
    inout(World) cs() inout pure nothrow @safe @nogc { return &_cs; }

    void takeOwnershipOf(ref MutableHalfOfWorld mutWo)
    {
        _cs.takeOwnershipOf(mutWo);
        _physicsDrawer.rebind(_cs.land, _cs.lookup);
    }

    void applyChangesToLand() {
        _physicsDrawer.applyChangesToLand(_cs.age);
    }

    void advance(in Ply[] pliesDueDuringThisAdvance)
    {
        ++_cs.age;
        pliesDueDuringThisAdvance[].each!(cd => applyPly(cd));

        updateNuke(); // sets lixInHatch = 0, affecting spawnLixxiesFromHatch
        spawnLixxiesFromHatches();
        updateLixxies();

        Hatch.maybePlaySound(_cs.age, _effect);
        if (_cs.isOvertimeRunning && _cs.someoneDoesntYetPreferGameToEnd) {
            _effect.announceOvertime(_cs.overtimeRunningSince,
                _cs.overtimeAtStartInPhyus);
        }
    }

    void dispose()
    {
        _cs.dispose;
        if (_physicsDrawer) {
            _physicsDrawer.dispose;
            _physicsDrawer = null;
        }
    }

private:
    OutsideWorld makeGypsyWagon(in Name na) pure nothrow @nogc
    {
        return OutsideWorld(cs, _physicsDrawer, _effect, na);
    }

    void applyPly(in Ply i)
    {
        assert (i.when == _cs.age,
            "increase the state's age manually before applying replay data");
        if (! _cs.tribes.contains(i.toWhom.owner))
            // Ignore bogus data that can come from anywhere
            return;
        auto tribe = _cs.tribes[i.toWhom.owner];
        if (tribe is null) {
            return;
        }
        if (tribe.hasNuked || _cs.nukeIsAssigningExploders) {
            // Game rule: After you call for the nuke, you may not assign
            // other things, nuke again, or do whatever we allow in the future.
            // During the nuke, nobody can assign or save lixes.
            return;
        }
        if (i.isAssignment) {
            const int id = i.toWhom.id;
            // never assert based on the content in Ply, which may have
            // been a maleficious attack from a third party, carrying a lix ID
            // that is not valid. If bogus data comes, do nothing.
            if (id < 0 || id >= tribe.lixlen)
                return;
            Lixxie lixxie = tribe.lixvec[id];
            assert (lixxie);
            if (! lixxie.priorityForNewAc(i.skill).isAssignable
                || ! tribe.canStillUse(i.skill)
                || (i.isDirectionallyForced && ! matchesDirection(i, lixxie))
            ) {
                return;
            }
            // Physics
            ++(tribe.skillsUsed[i.skill]);
            OutsideWorld ow = makeGypsyWagon(i.toWhom);
            lixxie.assignManually(&ow, i.skill);

            _effect.addAssignment(_cs.age, i.toWhom, lixxie.foot, i.skill,
                Sound.assignByReplay);
        }
        else if (i.isNuke) {
            tribe.recordNukePressedAt(_cs.age);
            _effect.addSound(_cs.age, i.toWhom, Sound.NUKE);
        }
    }

    static bool matchesDirection(in Ply p, in Lixxie li)
    pure nothrow @safe @nogc
    {
        final switch (p.lixShouldFace) {
            case Ply.LixShouldFace.unknown: return true;
            case Ply.LixShouldFace.left: return li.facingLeft;
            case Ply.LixShouldFace.right: return li.facingRight;
        }
    }

    void spawnLixxiesFromHatches()
    {
        foreach (tribe; _cs.tribes.allTribesEvenNeutral) {
            if (tribe.phyuOfNextSpawn() != _cs.age) {
                continue;
            }
            // the only interesting part of OutsideWorld right now is the
            // lookupmap inside the current state. Everything else will be
            // passed anew when the lix are updated.
            auto ow = makeGypsyWagon(Name(tribe.style, tribe.lixlen));
            tribe.spawnLixxie(&ow);
        }
    }

    void updateNuke()
    {
        if (! _cs.nukeIsAssigningExploders)
            return;
        foreach (tribe; _cs.tribes.allTribesEvenNeutral) {
            tribe.stopSpawningAnyMoreLixBecauseWeAreNuking();
            foreach (int lixID, lix; tribe.lixvec.enumerate!int) {
                if (! lix.healthy || lix.ploderTimer > 0)
                    continue;
                OutsideWorld ow = makeGypsyWagon(Name(tribe.style, lixID));
                lix.assignManually(&ow, Ac.exploder);
                break; // only one lix per tribe is hit by the nuke per update
            }
        }
    }

    void updateLixxies()
    {
        version (tharsisprofiling)
            Zone zone = Zone(profiler, "PhysSeq updateLixxies()");
        bool anyFlingers = false;

        void foreachLix(void delegate(Tribe, in int, Lixxie) func)
        {
            version (assert) {
                Style previousTribe = Style.min;
            }
            foreach (tribe; _cs.tribes.allTribesEvenNeutral) {
                version (assert) {
                    assert (previousTribe <= tribe.style);
                    previousTribe = tribe.style;
                }
                foreach (int lixID, lixxie; tribe.lixvec.enumerate!int)
                    func(tribe, lixID, lixxie);
            }
        }

        void performFlingersUnmarkOthers()
        {
            foreachLix((Tribe tribe, in int lixID, Lixxie lixxie) {
                lixxie.setNoEncountersNoBlockerFlags();
                if (lixxie.ploderTimer != 0) {
                    auto ow = makeGypsyWagon(Name(tribe.style, lixID));
                    handlePloderTimer(lixxie, &ow);
                }
                if (lixxie.updateOrder == PhyuOrder.flinger) {
                    lixxie.marked = true;
                    anyFlingers = true;
                    auto ow = makeGypsyWagon(Name(tribe.style, lixID));
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
                auto ow = makeGypsyWagon(Name(tribe.style, lixID));
                lixxie.applyFlingXY(&ow);
            });
        }

        void performUnmarked(PhyuOrder uo)
        {
            foreachLix((Tribe tribe, in int lixID, Lixxie lixxie) {
                if (! lixxie.marked && lixxie.updateOrder == uo) {
                    lixxie.marked = true;
                    auto ow = makeGypsyWagon(Name(tribe.style, lixID));
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
}
