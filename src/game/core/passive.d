module game.core.passive;

/* Stuff that needs to be done each calc() of the game, but that is not
 * about assignments or nukes at all. Even cancelling the replay upon LMB
 * is not here, it's in calcActive.
 *
 * calcPassive (the stuff in here) runs before calcActive (new assignments)
 * and game.physseq (updating physics with replayed and new assignments).
 */

import optional;

import basics.alleg5;
import basics.globals;
import game.core.assignee;
import game.core.game;
import game.panel.tooltip;
import graphic.camera.mapncam;
import gui;
import hardware.keyboard;
import hardware.mousecur;
import hardware.sound;
import net.name;

package:

void calcPassive(
    Game game,
    in UnderCursor underCursor,
) { with (MouseCursor)
{
    game.map.calcZoomAndScrolling();
    if (underCursor.best.empty) {
        game.activateOrDeactivateTweaker(no!Name);
    }
    else {
        Optional!Name arg = underCursor.best.front.name;
        game.activateOrDeactivateTweaker(arg);
    }

    if (! underCursor.best.empty) {
        game.chooseCursorAndTooltipFor(underCursor.best.front);
    }
    else if (game.canWeClickAirNowToCutGlobalFuture) {
        game._mapClickExplainer.suggestTooltip(Tooltip.ID.cancelReplay);
        mouseCursor.want(Sidekick.scissors);
    }
    mouseCursor.want(game.map.isHoldScrolling ? Arrows.scroll
        : forcingLeft ? Arrows.left
        : forcingRight ? Arrows.right
        : Arrows.none);

    if (game.map.suggestHoldScrollingTooltip) {
        game._panelExplainer.suggestTooltip(Tooltip.ID.holdToScroll);
    }
    if (game.pan.highlightGoalsExecute) {
        game._altickHighlightGoalsUntil = timerTicks + ticksPerSecond * 3 / 2;
    }
}}

///////////////////////////////////////////////////////////////////////////////

private:

void chooseCursorAndTooltipFor(Game game, in Assignee best)
{
    mouseCursor.want(MouseCursor.Shape.openSquare);
    game._effect.localStyle = best.name.owner;

    if (game.canAssignTo(best) && game.canWeClickAirNowToCutGlobalFuture) {
        mouseCursor.want(MouseCursor.Sidekick.insert);
        game._mapClickExplainer.suggestTooltip(Tooltip.ID.purelyInsert);
        const n = game.nurse.numFutureAssignmentsOf(best.name);
        if (n >= 1) {
            game._mapClickExplainer.suggestNumFuturePliesToReplace(n);
        }
    }
}

void activateOrDeactivateTweaker(Game game, in Optional!Name toHighlight)
{
    if (game.pan.tweakerIsOn) {
        game._tweaker.shown = true;
        game._tweaker.formatButtonsAccordingTo(
            game.nurse.constReplay.allPlies,
            game.nurse.now, toHighlight);
    }
    else if (game._tweaker.shown) {
        game._tweaker.shown = false;
        gui.requireCompleteRedraw();
    }
    game.map.choose(game._tweaker.shown ? MapAndCamera.CamSize.withTweaker
        : MapAndCamera.CamSize.fullWidth);
}
