module game.gameacti;

import std.typecons : Rebindable;

import basics.nettypes;
import basics.user; // hotkeys
import game;
import gui : SkillButton;
import hardware.keyboard;
import hardware.mouse;
import hardware.mousecur;
import hardware.sound;
import lix;

package ReplayData
newReplayDataForNextUpdate(Game game)
{
    ReplayData data;
    data.player = game.masterLocal.number;
    data.update = game.cs.update + 1;
    return data;
}



package void
calcActive(Game game) { with (game)
{
    game.handleSpawnIntervalButtons();
    game.handleNukeButton();
    // Selection of skills in the panel aren't checked here anymore.
    // They aren't replay data, so that check went into gamepl_c.cpp.

    if (! pan.isMouseHere) {
        auto potAss = game.findPotentialAssignee();
        if (potAss.lixxie !is null)
            game.assignToPotentialAssignee(potAss);
    }
    else
        pan.stats.targetDescriptionNumber = 0;
}}



private struct PotentialAssignee {
    Rebindable!(const(Lixxie)) lixxie;
    int id;
    int priority;
    double distanceToCursor;

    // Compare lixes for, priority:
    // 1. priority number from lixxie.priorityForNewAc
    // 2. what is closer to the mouse cursor (if priority is equal)
    // 3. what has spawned earlier (if still equal)
    // Holding the priority inversion key, or right mouse button (configurable
    // in the options) inverts the sorting of (1.), but not of the others.
    bool isBetterThan(in ref PotentialAssignee rhs) const {
        immutable bool priorityInvert = (
               (mouseHeldRight  && basics.user.priorityInvertRight)
            || (mouseHeldMiddle && basics.user.priorityInvertMiddle)
            || (hardware.keyboard.keyHeld(basics.user.keyPriorityInvert))
        );
        return lixxie    is null ? false
            : rhs.lixxie is null ? true
            : priority > rhs.priority ? ! priorityInvert
            : priority < rhs.priority ?   priorityInvert
            : distanceToCursor > rhs.distanceToCursor ? true
            : distanceToCursor < rhs.distanceToCursor ? false
            : id < rhs.id;
    }
}



private void
handleSpawnIntervalButtons(Game game) { with (game)
{
    if (multiplayer)
        // rulings forbid changing the spawn interval in multiplayer
        return;

    // uncomment and implement after putting spawnint buttons into panel
    /+
    immutable int cur = pan.spawnintCur.get_spawnint();

    if (cur != tribe.spawnint_slow) {
        if (pan.spawnint_slow.get_execute_right())
            pan.spawnint_cur.set_spawnint(tribe.spawnint_slow);
        else if (pan.spawnint_slow.get_execute_left())
            pan.spawnint_cur.set_spawnint(cur + 1);
    }

    if (cur != tribe.spawnint_fast) {
        if (pan.spawnint_cur .get_execute_right())
            pan.spawnint_cur.set_spawnint(tribe.spawnint_fast);
        else if (pan.spawnint_cur.get_execute_left())
            pan.spawnint_cur.set_spawnint(cur - 1);
    }
    +/
}}



private void handleNukeButton(Game game) { with (game)
{
    /+
    // Atombombe
    if (pan.get_nuke_doubleclicked()) {
        // set_on() kommt zwar auch im Update, aber wenn wir das
        // hier immer machen, sieht es besser aus. Gleiches gilt fuer
        // den Sound, ist wie beim normalen Anklicken.
        pan.nuke_single.set_on();
        pan.nuke_multi .set_on();
        pan.pause      .set_off();
        Replay::Data data = new_replay_data();
        data.action       = Replay::NUKE;
        replay.add(data);
        Network::send_replay_data(data);
        effect.add_sound(cs.update + 1, *trlo, 0, Sound::NUKE);
        Sound::play_loud(Sound::NUKE);
    }
    +/
}}



private bool forceLeft()
{
    return   hardware.keyboard.keyHeld(basics.user.keyForceLeft)
        && ! hardware.keyboard.keyHeld(basics.user.keyForceRight);
}

private bool forceRight()
{
    return ! hardware.keyboard.keyHeld(basics.user.keyForceLeft)
        &&   hardware.keyboard.keyHeld(basics.user.keyForceRight);
}




private PotentialAssignee
findPotentialAssignee(Game game) { with (game)
{
    assert (tribeLocal);

    PotentialAssignee best; // clicks go to her, priority is already considered
    PotentialAssignee worst; // if different from best, make tooltip
    PotentialAssignee described; // her action is described on the panel

    int lixesUnderCursor = 0;

    bool leftFound  = false; // if both left/right true,
    bool rightFound = false; // make a tooltip

    const(SkillButton) currentSkill = game.pan.currentSkill;

    assert (map.zoom > 0);

    immutable int cursorThicknessOnLand = 12 / map.zoom;
    immutable int mmldX = cursorThicknessOnLand +  2; // + lix thickness
    immutable int mmldU = cursorThicknessOnLand + 15; // + lix height
    immutable int mmldD = cursorThicknessOnLand +  0;

    immutable int mx = map.mouseOnLandX;
    immutable int my = map.mouseOnLandY;

    // DTODO: Find out why we were traversing the lixvec backwards in C++
    // for (LixIt i =  --trlo->lixvec.end(); i != --trlo->lixvec.begin(); --i)
    foreach (int id, const(Lixxie) lixxie; tribeLocal.lixvec) {
        immutable int distX = map.distanceX(lixxie.ex, mx);
        immutable int distY = map.distanceY(lixxie.ey, my);

        if (   distX <= mmldX && distX >= -mmldX
            && distY <= mmldD && distY >= -mmldU
            && lixxie.cursorShouldOpenOverMe
        ) {
            ++lixesUnderCursor;
            PotentialAssignee potAss = game.generatePotentialAssignee(
                lixxie, id, mx, my, mmldD - mmldU, currentSkill);
            if (potAss.isBetterThan(described)) {
                described = potAss;
            }
            comparePotentialWithBestWorst(potAss, best, worst,
                leftFound, rightFound);
        }
        // end if under cursor
    }
    // end loop through all lixes

    if (best.lixxie !is null && best.lixxie !is worst.lixxie)
        pan.stats.suggestTooltipPriorityInvert();

    if (leftFound && rightFound)
        pan.stats.suggestTooltipForceDirection();

    mouseCursor.xf = (forceLeft ? 1 : forceRight ? 2 : mouseCursor.xf);
    mouseCursor.yf = (lixesUnderCursor > 0);

    pan.stats.targetDescriptionNumber = lixesUnderCursor;
    pan.stats.targetDescriptionLixxie = described.lixxie;

    if (best.lixxie !is null
        && currentSkill !is null
        && currentSkill.number != 0
        && currentSkill.skill == best.lixxie.ac
    ) {
        if (best.lixxie.ac == Ac.BUILDER)
            pan.stats.suggestTooltipBuilders();
        else if (best.lixxie.ac == Ac.PLATFORMER)
            pan.stats.suggestTooltipPlatformers();
    }

    return best;
}}
// end void findPotentialAssignee()



private PotentialAssignee
generatePotentialAssignee(
    Game game,
    in Lixxie lixxie,
    in int id,
    in int mx,
    in int my,
    in int dMinusU,
    in SkillButton currentSkill
) {
    PotentialAssignee potAss;
    potAss.lixxie = lixxie;
    potAss.id = id;
    potAss.distanceToCursor = game.map.hypotSquared(mx, my, lixxie.ex,
                                                    lixxie.ey + dMinusU/2);
    if (currentSkill !is null)
        // true = consider personal settings like multiple builders
        potAss.priority = lixxie.priorityForNewAc(currentSkill.skill, true);
    else
        // we shouldn't need it, leftover from C++
        potAss.priority = 1;

    return potAss;
}



private void
comparePotentialWithBestWorst(
    in ref PotentialAssignee potAss,
    ref PotentialAssignee best,
    ref PotentialAssignee worst,
    ref bool anyFoundLeft,
    ref bool anyFoundRight,
) {
    assert (potAss.lixxie !is null);

    if (potAss.priority <= 1)
        // This function is only concerned with possible assignments,
        // not with who should be counted on the panel even if unassignable.
        return;

    immutable bool eligibleAccordingToDirSelect =
           ! (potAss.lixxie.facingLeft  && forceRight)
        && ! (potAss.lixxie.facingRight && forceLeft);

    if (eligibleAccordingToDirSelect) {
        if (potAss.isBetterThan(best))
            best = potAss;
        if (worst.isBetterThan(potAss))
            worst = potAss;
    }
}



private void
assignToPotentialAssignee(
    Game game,
    in ref PotentialAssignee potAss) { with (game)
{
    if (! hardware.mouse.mouseClickLeft || potAss.lixxie is null)
        // assign on left clicks; if no click, don't do anything
        return;

    SkillButton currentSkill = pan.currentSkill;
    if (potAss.lixxie is null
        || currentSkill is null
        || currentSkill.number == 0
    ) {
        hardware.sound.playLoud(Sound.PANEL_EMPTY);
        return;
    }

    hardware.sound.playLoud(Sound.ASSIGN);
    effect.addSound(cs.update + 1, tribeID(tribeLocal),
                    potAss.id, Sound.ASSIGN);

    // Decrease the visible number on the panel. This is mostly eye candy.
    // It doesn't affect physics, including judging what's coming in over
    // the network, but it affects our assignment code, e.g. further up
    // in this very function on two rapid assignments.
    assert (replay);
    if (replay.getOnUpdateLixClicked(cs.update + 1, potAss.id,
                                     currentSkill.skill)
        && currentSkill.number != skillInfinity
    ) {
        currentSkill.number = currentSkill.number - 1;
    }

    pan.pause.on = false;
    // DTODO: Cut off the replay in case we are replaying right now.
    // We should go into gameacti even while replaying. This needs lots of
    // thinking, because we don't want to cut off the assignments we are
    // making for the next update, but we want to cut off what has been
    // (scheduled for the next update) a minute ago during our last attempt.

    ReplayData data = game.newReplayDataForNextUpdate();
    data.action     = forceLeft  ? RepAc.ASSIGN_LEFT
                    : forceRight ? RepAc.ASSIGN_RIGHT
                    :              RepAc.ASSIGN;
    data.skill      = currentSkill.skill;
    data.toWhichLix = potAss.id;
    replay.add(data);

    // DTODONETWORK
    // Network::send_replay_data(data);
}}
// end void assignToPotentialAssignee()