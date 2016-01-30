module game.core.calc;

import std.algorithm; // all

import basics.user;
import basics.cmdargs;
import game.core.game;
import game.gui.wduring;
import game.core.active;
import game.core.passive;
import game.core.speed;
import gui;
import hardware.keyboard;

package void
implGameCalc(Game game)
{
    assert (game.runmode == Runmode.INTERACTIVE);
    if (game.modalWindow) {
        game.calcModalWindow;
    }
    else if (keyTapped(keyGameExit)) {
        game.createModalWindow;
    }
    else {
        game.calcPassive();
        game.calcActive();
        game.updatePhysicsAccordingToSpeedButtons();
        if (game.isFinished)
            game.createModalWindow;
    }
}

private bool
isFinished(const(Game) game) { with (game)
{
    assert (nurse);
    if (runmode == Runmode.VERIFY)
        return ! nurse.stillPlaying();
    else
        return ! nurse.stillPlaying() && effect.nothingGoingOn;
}}

private void
createModalWindow(Game game)
{
    game.modalWindow =
        // multiplayer && ! replaying ? : ? : ? :
        game.isFinished
        ? new WindowEndSingle(game.tribeLocal, game.nurse.replay, game.level)
        : new WindowDuringOffline(game.nurse.replay, game.level);
    addFocus(game.modalWindow);
}

private void
calcModalWindow(Game game) { with (game)
{
    void killWindow()
    {
        rmFocus(modalWindow);
        modalWindow = null;
        game.setLastUpdateToNow();
    }
    assert (modalWindow);
    if (modalWindow.resume) {
        killWindow();
    }
    else if (modalWindow.restart) {
        game.nurse.restartLevel();
        game.setLastUpdateToNow();
        killWindow();
    }
    else if (modalWindow.exitGame) {
        _gotoMainMenu = true;
        killWindow();
    }
}}
