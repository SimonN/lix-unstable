module physics.statinit;

import std.algorithm;
import std.array;
import std.conv;
import std.typecons;

import basics.alleg5;
import basics.globals;
import basics.help; // len
import file.option;
import graphic.gadget;
import graphic.torbit;
import file.replay;
import level.level;
import net.permu;
import physics.lixxie.fields;
import physics.state;
import physics.tribe;
import physics.handimrg;
import tile.phymap;
import tile.gadtile;

public:

struct GameStateInitCfg {
    Level level;
    MergedHandicap[Style] tribes;
    Permu permu;
}

package:

GameState newZeroState(in GameStateInitCfg cfg)
in {
    assert (cfg.tribes.length >= 1);
}
do {
    GameState s;
    s.refCountedStore.ensureInitialized();
    s.land   = new Torbit(Torbit.Cfg(cfg.level.topology));
    s.lookup = new Phymap(cfg.level.topology);
    cfg.level.drawTerrainTo(s.land, s.lookup);

    s.preparePlayersButNotNeutralsYet(cfg);
    s.prepareGadgets(cfg.level);
    s.assignTribesToGoals(cfg.permu);
    s.foreachGadget((Gadget g) {
        g.drawLookup(s.lookup);
    });
    s.prepareNeutrals(cfg.level);
    s.age = s.isBattle ? Phyu(0) : Phyu(45); // start quickly in 1-player
    s.overtimeAtStartInPhyus = s.isBattle
        ? cfg.level.overtimeSeconds * phyusPerSecondAtNormalSpeed : 0;
    return s;
}

private:

void preparePlayersButNotNeutralsYet(GameState state, in GameStateInitCfg cfg)
in {
    assert (state.tribes.numPlayerTribes == 0);
    assert (cfg.tribes.length >= 1);
}
do {
    const nukeRule = cfg.tribes.length > 1 && cfg.level.overtimeSeconds == 0
        ? Tribe.RuleSet.MustNukeWhen.raceToFirstSave
        : Tribe.RuleSet.MustNukeWhen.normalOvertime;
    foreach (style, mergedHandicap; cfg.tribes) {
        state.tribes.add(Tribe.RuleSet(
            style,
            cfg.level.initial,
            cfg.level.spawnint,
            cfg.level.skills,
            nukeRule,
            mergedHandicap,
        ));
    }
}

void prepareGadgets(GameState state, in Level level)
{
    assert (state.lookup);
    void instantiateGadgetsFromArray(T)(ref T[] gadgetVec, GadType tileType)
    {
        foreach (ref occ; level.gadgets[tileType]) {
            gadgetVec ~= cast (T) Gadget.factory(state.lookup, occ);
            assert (gadgetVec[$-1], occ.toIoLine.toString);
            // don't draw to the lookup map yet, we may remove some goals first
        }
    }
    instantiateGadgetsFromArray(state.hatches,  GadType.HATCH);
    instantiateGadgetsFromArray(state.goals,    GadType.GOAL);
    instantiateGadgetsFromArray(state.traps,    GadType.TRAP);
    instantiateGadgetsFromArray(state.waters,   GadType.WATER);
    instantiateGadgetsFromArray(state.flingPerms, GadType.FLINGPERM);
    instantiateGadgetsFromArray(state.flingTrigs, GadType.FLINGTRIG);
}

void prepareNeutrals(GameState state, in Level level)
{
    if (level.gadgets[GadType.prePlacedNeutral].empty) {
        return;
    }
    state.tribes.add(Tribe.RuleSet(Style.neutral));
    foreach (pre; level.gadgets[GadType.prePlacedNeutral]) {
        auto ow = OutsideWorld(state, null, null,
            Passport(Style.neutral, state.tribes[Style.neutral].lixlen));
        state.tribes[Style.neutral].spawnLixxiePrePlaced(&ow, pre);
    }
}

void assignTribesToGoals(GameState state, in Permu permu)
in {
    import std.format;
    assert (state.hatches.len, "we'll do modulo on the hatches, 0 is bad");
    assert (state.tribes.numPlayerTribes, "can't assign goals to 0 players");
    assert (permu.len == state.tribes.numPlayerTribes,
        format!"permu length mismatch: permu len = %d, playable tribes = %d"
            (permu.len, state.tribes.numPlayerTribes));
}
out {
    assert (state.hatches.all!(h => ! h.tribes.empty));
}
do { with (state)
{
    immutable numTribes = state.tribes.numPlayerTribes;
    while (hatches.len % numTribes != 0 && numTribes % hatches.len != 0)
        hatches = hatches[0 .. $-1];
    assert (hatches.len);
    while (goals.len
        && goals.len % numTribes != 0 && numTribes % goals.len != 0)
        goals = goals[0 .. $-1];

    auto stylesInPlay = tribes.playerTribes.map!(tr => tr.style).array;
    stylesInPlay.sort();

    // Permu 0 3 1 2 for 2 goals and tribes red, orange, yellow, purple means:
    // -> Red & purple get goal 0 because their slots are 0 mod 2.
    // -> Orange & yellow get goal 1 because their slots are 1 mod 2.
    // Permu 0 2 1 for 6 goals and tribes red, orange, yellow means:
    // -> Red gets goal 0 & 3. Orange gets 2 & 5. Yellow gets 1 & 4.
    foreach (size_t i, style; stylesInPlay) {
        immutable int slot = permu[i.to!int];
        tribes[style].nextHatch = slot % hatches.len;
        for (int j = slot % hatches.len; j < hatches.len; j += numTribes)
            hatches[j].addTribe(style);
        if (goals.len == 0)
            continue;
        for (int j = slot % goals.len; j < goals.len; j += numTribes)
            goals[j].addTribe(style);
    }
}}
