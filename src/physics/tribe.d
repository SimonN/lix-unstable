module physics.tribe;

/* A Tribe is a colored team. It can have multiple players, when a multiplayer
 * team game is played. Each tribe has a color, number of lixes, etc.
 * In singleplayer, there is one tribe with one master.
 *
 * Tribe (as physics in general) doesn't know about players.
 * If player info is needed, the game must fetch it from the replay.
 */

import std.algorithm;

import enumap;
import optional;

import basics.globals;
import basics.help;
import basics.rect;
import lix;
import level.level; // spawnintMax
import net.repdata;
import physics.fracint;
import physics.handimrg;
import physics.score;

final class Tribe {
    immutable RuleSet rules;
    ValueFields valueFields;
    alias valueFields this;

    LixxieImpl[] lixvecImpl;

    struct RuleSet {
        enum MustNukeWhen : ubyte {
            normalOvertime,
            raceToFirstSave,
        }

        Style style;
        int initialLixInHatchWithoutHandicap;
        int spawnInterval; // number of physics updates until next spawn
        Enumap!(Ac, int) initialSkillsWithoutHandicap; // may be skillInfinity
        MustNukeWhen mustNukeWhen;
        MergedHandicap handicap;
    }

    private static struct ValueFields {
    private:
        Optional!Phyu _updatePreviousSpawn = none;
        Optional!Phyu _firstScoring = none;
        Optional!Phyu _recentScoring = none;
        Optional!Phyu _outOfLixSince = none;
        Optional!Phyu _nukePressedAt = none;

        int _lixSpawned; // 0 at start
        int _lixOut;
        int _lixLeaving; // these have been scored, but keep game running
        int _lixSaved; // query with score()

    public:
        Enumap!(Ac, int) skillsUsed;
        int nextHatch; // Initialized by the state initalizer with the permu.
                       // We don't need the permu afterwards for spawns.
    }

    enum Phyu firstSpawnWithoutHandicap = Phyu(60);

public:
    this(in RuleSet r) { rules = r; }

    this(in Tribe rhs)
    {
        assert (rhs, "don't copy-construct from a null Tribe");
        valueFields = rhs.valueFields;
        lixvecImpl = rhs.lixvecImpl.clone; // only value types since 2017-09!
        rules = rhs.rules;
    }

    Tribe clone() const { return new Tribe(this); }

    auto lixvec() @nogc // mutable. For const, see 5 lines below
    {
        Lixxie f(ref LixxieImpl value) { return &value; }
        return lixvecImpl.map!f;
    }

    auto lixvec() const @nogc
    {
        ConstLix f(ref const(LixxieImpl) value) { return &value; }
        return lixvecImpl[].map!f;
    }

    const pure nothrow @safe @nogc {
        Style style() { return rules.style; }

        int lixlen() { return lixvecImpl.len; }

        bool outOfLix() { return _lixOut == 0 && lixInHatch == 0; }
        bool doneAnimating() { return outOfLix() && ! _lixLeaving; }

        int lixOut() { return _lixOut; }
        int lixInHatch() {
            return rules.handicap.initialLix.scale(
                rules.initialLixInHatchWithoutHandicap) - _lixSpawned;
        }

        Optional!Phyu phyuOfNextSpawn()
        {
            if (lixInHatch == 0) {
                return no!Phyu;
            }
            return some(_updatePreviousSpawn.match!(
                () => Phyu(firstSpawnWithoutHandicap
                    + rules.handicap.delayInPhyus),
                (prev) => Phyu(prev + rules.spawnInterval),
            ));
        }

        bool canStillUse(in Ac ac)
        {
            immutable int left = usesLeft(ac);
            return left > 0 || left == skillInfinity;
        }

        int usesLeft(in Ac ac)
        {
            if (rules.initialSkillsWithoutHandicap[ac] == skillInfinity) {
                return skillInfinity;
            }
            immutable int atStart = rules.handicap.initialSkills.scale(
                rules.initialSkillsWithoutHandicap[ac])
                + rules.handicap.extraSkills;
            return atStart - skillsUsed[ac];
        }

        Score score()
        {
            Score ret;
            ret.style = style;
            ret.lixSaved = FracInt(_lixSaved, rules.handicap.score);
            ret.lixYetUnsavedRaw = _lixOut + lixInHatch;
            ret.prefersGameToEnd = wantsToAbort;
            return ret;
        }

        bool hasScored()
        {
            immutable ret = _lixSaved > 0;
            assert (ret != _firstScoring.empty);
            return ret;
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    // Mutation
    ///////////////////////////////////////////////////////////////////////////

    void recordSpawnedFromHatch()
    in { assert (this.lixInHatch > 0); }
    out { assert (this.lixInHatch >= 0 && this._lixOut >= 0); }
    do {
        ++_lixSpawned;
        ++_lixOut;
    }

    void recordOutToLeaver(in Phyu now)
    in {
        assert (this._lixOut > 0);
        assert (this._outOfLixSince.empty);
    }
    out {
        assert (this._lixOut >= 0 && this._lixLeaving >= 0);
    }
    do {
        --_lixOut;
        ++_lixLeaving;
        if (outOfLix)
            _outOfLixSince = now;
    }

    void recordLeaverDone()
    in { assert (this._lixLeaving > 0); }
    out { assert (this._lixOut >= 0 && this._lixLeaving >= 0); }
    do { --_lixLeaving; }

    void stopSpawningAnyMoreLixBecauseWeAreNuking()
    {
        _lixSpawned = rules.handicap.initialLix.scale(
            rules.initialLixInHatchWithoutHandicap);
    }

    void addSaved(in Style fromWho, in Phyu now)
    {
        _recentScoring = now;
        if (_lixSaved == 0)
            _firstScoring = now;
        ++_lixSaved;
    }

    void returnSkills(in Ac ac, in int amount)
    {
        skillsUsed[ac] -= amount;
    }

    void spawnLixxie(OutsideWorld* ow)
    in {
        if (! ow.state.hatches[this.nextHatch].hasTribe(this.style)) {
            import std.string;
            string msg = format("Style %s spawns from wrong hatch #%d.",
                this.style, this.nextHatch);
            foreach (const size_t i, hatch; ow.state.hatches) {
                msg ~= format("\nHatch #%d has styles:", i);
                foreach (Style st; hatch.tribes) {
                    msg ~= " " ~ styleToString(st);
                }
            }
            assert (false, msg);
        }
    }
    do {
        const hatch = ow.state.hatches[nextHatch];
        LixxieImpl newLix = LixxieImpl(ow, Point(
            hatch.loc.x + hatch.tile.trigger.x - 2 * hatch.spawnFacingLeft,
            hatch.loc.y + hatch.tile.trigger.y));
        if (hatch.spawnFacingLeft)
            newLix.turn();
        lixvecImpl ~= newLix;
        recordSpawnedFromHatch();
        _updatePreviousSpawn = ow.state.update;
        do {
            nextHatch = (nextHatch + 1) % ow.state.hatches.len;
        }
        while (! ow.state.hatches[nextHatch].hasTribe(this.style));
    }


    ///////////////////////////////////////////////////////////////////////////
    // Nuke
    ///////////////////////////////////////////////////////////////////////////

    void recordNukePressedAt(Phyu u) @nogc { _nukePressedAt = u; }

    const pure nothrow @safe @nogc {
        bool hasNuked() { return ! _nukePressedAt.empty; }
        bool wantsToAbort() { return ! wantsToAbortAt.empty; }
        bool triggersOvertime() { return ! triggersOvertimeAt.empty; }

        private Optional!Phyu finishedRaceAt()
        {
            return rules.mustNukeWhen == RuleSet.MustNukeWhen.raceToFirstSave
                ? _firstScoring : no!Phyu;
        }

        Optional!Phyu wantsToAbortAt()
        {
            return optmin(_nukePressedAt, _outOfLixSince, finishedRaceAt);
        }

        Optional!Phyu triggersOvertimeAt()
        {
            if (! hasScored) {
                return no!Phyu;
            }
            return optmin(
                hasNuked ? optmax(_nukePressedAt, _firstScoring) : no!Phyu,
                outOfLix ? optmax(_outOfLixSince, _firstScoring) : no!Phyu,
                finishedRaceAt);
        }
    }
}

/*
 * optmin(x,  y)  == min(x, y).
 * optmin(x,  no) == x.
 * optmin(no, no) == no.
 */
alias optmin = optreduce!min;
alias optmax = optreduce!max;

template optreduce(alias pairingFunc) {
    Optional!Phyu optreduce(R)(R r) pure nothrow @safe @nogc
    {
        return r.fold!optpair(no!Phyu);
    }

    Optional!Phyu optreduce(Optional!Phyu[] args...) pure nothrow @safe @nogc
    {
        return args[].fold!optpair(no!Phyu);
    }

    private Optional!Phyu optpair(in Optional!Phyu a, in Optional!Phyu b
    ) pure nothrow @safe @nogc
    {
        if (a.empty) return b;
        if (b.empty) return a;
        Phyu ret = pairingFunc(a.front, b.front);
        return ret.some;
    }
}

unittest {
    immutable x = Optional!Phyu(Phyu(8));
    immutable y = Optional!Phyu(Phyu(7));
    immutable z = no!Phyu;
    assert (optmin(x, y) == y);
    assert (optmin(y, z) == y);
    assert (optmin(x, z) == x);
    assert (optmin(z, y, z) == y);
    assert (optmin(z, z, z) == no!Phyu);
    assert (optmin() == no!Phyu);
}
