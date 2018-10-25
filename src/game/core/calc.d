module game.core.calc;

import std.algorithm;

import optional;

import file.option;
import basics.cmdargs;
import game.core.game;
import game.window.base;
import game.core.active;
import game.core.passive;
import game.core.speed;
import game.panel.tooltip;
import gui;
import hardware.keyset;
import physics.score;

package void
implGameCalc(Game game) { with (game)
{
    void noninputCalc()
    {
        if (_netClient)
            _netClient.calc();
        game.updatePhysicsAccordingToSpeedButtons();
    }
    if (modalWindow) {
        game.calcModalWindow;
        noninputCalc();
    }
    else if (keyGameExit.keyTapped) {
        if (multiplayer) {
            modalWindow = new ReallyExitWindow();
            addFocus(game.modalWindow);
        }
        else {
            _gotoMainMenu = true;
        }
    }
    else {
        game.calcPassive();
        game.calcActive();
        noninputCalc();
        game.atEndOfGame();
    }
}}

private:

void calcModalWindow(Game game) { with (game)
{
    assert (modalWindow);
    if (modalWindow.exitGame) {
        _gotoMainMenu = true;
    }
    if (modalWindow.exitGame || modalWindow.resume) {
        rmFocus(modalWindow);
        modalWindow = null;
        game.setLastPhyuToNow();
    }
}}

void atEndOfGame(Game game) { with (game)
{
    if (! nurse.doneAnimating()) {
        // Not end of game yet
        return;
    }
    // Physics are finished
    if (! multiplayer && ! singleplayerHasWon) {
        // The nuke button is checked here in addition to checking it during
        // physics in game.core.active. In game.core.active, it generates
        // the nuke input for the replay, but we won't process any further
        // replay updates after all lixes have died. Thus, after all lixes
        // have died, cancel the game immediately here without affecting
        // physics.
        if (pan.nukeDoubleclicked)
            _gotoMainMenu = true;
        else
            pan.suggestTooltip(Tooltip.ID.framestepOrQuit);
    }
    assert (_effect,
        "Game should only run with an instantiated EffectManager,"
        ~ " not with a NullEffectManager or a null reference");
    // Don't immediately exit. Wait for the user to exit manually.
    if (_effect.nothingGoingOn) {
        // Physics and animations are finished, nothing else to see
        if (multiplayer || singleplayerHasWon || singleplayerHasNuked)
            _gotoMainMenu = true;
        if (view.printResultToConsole)
            _chatArea.printScores(nurse.scores, nurse.constReplay, localStyle);
    }
}}
