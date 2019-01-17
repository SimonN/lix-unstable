module game.core.draw;

import std.algorithm;
import std.conv; // replay sign
import std.math; // sin, for replay sign
import std.range : retro;
import std.string; // format

import optional;

import basics.alleg5;
import basics.globals; // replay sign
import file.option : showFPS;
import game.core.game;
import game.panel.tooltip;
import graphic.color;
import graphic.cutbit; // replay sign
import graphic.gadget;
import graphic.internal;
import graphic.map;
import graphic.torbit;
import hardware.display;
import hardware.music;
import hardware.tharsis;
import physics.tribe;

package void
implGameDraw(Game game) { with (game)
{
    version (tharsisprofiling)
        auto zo = Zone(profiler, "game entire implGameDraw()");
    nurse.applyChangesToLand();
    {
        version (tharsisprofiling)
            auto zo2 = Zone(profiler, "game entire drawing to map");
        // speeding up drawing by setting the drawing target now.
        // This RAII struct is used in each innermost loop, too, but it does
        // nothing except comparing two pointers there if we've set stuff here.
        auto drata = TargetTorbit(map);
        Alcol levBg = color.makecol(level.bgRed, level.bgGreen, level.bgBlue);
        map.clearScreenRect(levBg);
        game.drawGadgets();

        if (modalWindow || ! pan.coolShadesAreOn || pan.isMouseHere) {
            game.drawLand();
            game.pingOwnGadgets();
        }
        else {
            _splatRuler.considerBackgroundColor(levBg);
            _splatRuler.determineSnap(nurse.constStateForDrawingOnly.lookup,
                map.mouseOnLand);
            _splatRuler.drawBelowLand(map);
            game.drawLand();
            game.pingOwnGadgets();
            _splatRuler.drawAboveLand(map);
        }
        _effect.draw(_chatArea.console);
        _effect.calc(); // No physics, so OK to calc here.
        game.drawAllLixes();
    }
    pan.showInfo(localTribe);
    foreach (sc; nurse.scores)
        pan.update(sc);
    pan.age = nurse.constStateForDrawingOnly.update;
    game.showSpawnIntervalOnHatches();

    auto drata = TargetBitmap(al_get_backbuffer(display));
    {
        version (tharsisprofiling)
            auto zo2 = Zone(profiler, "game draws map to screen");
        map.drawCamera();
    }
    game.drawReplaySign();
    with (game.nurse.constStateForDrawingOnly)
        if (! isMusicPlaying && update >= updateFirstSpawn)
            suggestRandomMusic();
}}
// end with(game), end implGameDraw()

private:

void drawGadgets(Game game) { with (game)
{
    version (tharsisprofiling)
        auto zone = Zone(profiler, "game draws gadgets");
    auto cs = nurse.constStateForDrawingOnly;

    cs.foreachConstGadget(delegate void (const(Gadget) g) {
        g.draw(localTribe.style);
    });
    if (cs.nuking && ! cs.tribes.byValue.all!(tr => tr.outOfLix)) {
        foreach (g; cs.goals)
            g.drawNoSign();
    }
}}

void pingOwnGadgets(Game game) { with (game)
{
    if (! multiplayer)
        return;
    immutable remains = _altickPingGoalsUntil - timerTicks;
    if (remains < 0) {
        // Usually, we haven't clicked the cool shades button.
        // Merely draw the own goals with semi-transparent extra lixes.
        foreach (g; nurse.gadgetsOfTeam(localTribe.style))
            g.drawExtrasOnTopOfLand(localTribe.style);
    }
    else {
        // Draw the glaring black-and-white rectangles.
        immutable int period = ticksPerSecond / 4;
        assert (period > 0);
        if (remains % period < period / 2)
            return; // draw nothing extra during the off-part of flashing
        foreach (g; nurse.gadgetsOfTeam(localTribe.style)) {
            enum th = 5; // thickness of the border
            Rect outer = Rect(g.loc - Point(th, th), g.xl + 2*th, g.yl + 2*th);
            Rect inner = Rect(g.loc, g.xl, g.yl);
            map.drawFilledRectangle(outer, color.white);
            map.drawFilledRectangle(inner, color.black);
            g.draw(localTribe.style);
        }
    }
}}

void drawLand(Game game)
{
    version (tharsisproftsriling)
        auto zone = Zone(profiler, "game draws land to map");
    game.map.loadCameraRect(game.nurse.constStateForDrawingOnly.land);
}

void drawAllLixes(Game game)
{
    version (tharsisprofiling)
        auto zone = Zone(profiler, "game draws lixes");
    void drawTribe(in Tribe tr)
    {
        tr.lixvec.retro.filter!(l => ! l.marked).each!(l => l.draw);
        tr.lixvec.retro.filter!(l => l.marked).each!(l => l.draw);
    }
    with (game) {
        foreach (otherTribe; nurse.constStateForDrawingOnly.tribes)
            if (otherTribe !is game.localTribe)
                drawTribe(otherTribe);
        import lix.fuse : drawAbilities; // onto opponents, behind our own
        localTribe.lixvec.retro.each!(l => drawAbilities(l));
        drawTribe(localTribe);

        _drawHerHighlit.match!(() {}, (passport) {
            pan.currentSkill.match!(() {}, (curSk) {
                nurse.drawBlueprint(passport, curSk.skill);
            });
            nurse.constStateForDrawingOnly.tribes[passport.style]
                .lixvec[passport.id].drawAgainHighlit();
        });
    }
}

void showSpawnIntervalOnHatches(Game game)
{
    game.pan.dontShowSpawnInterval();
    if (game.nurse.constStateForDrawingOnly.hatches.any!(h =>
        game.map.isPointInRectangle(game.map.mouseOnLand, h.rect)))
        game.pan.showSpawnInterval(game.localTribe.spawnint);
}

void drawReplaySign(Game game)
{
    if (! game.replaying)
        return;
    if (game.view.showReplaySign) {
        const(Cutbit) rep = getInternal(fileImageGameReplay);
        rep.drawToCurrentAlbitNotTorbit(Point(0,
            (rep.yl/5 * (1 + sin(timerTicks * 0.08f))).to!int));
    }
    if (game.view.canInterruptReplays && ! game.pan.isMouseHere
        && ! showFPS.value // power user setting, it overrides us
    ) {
        game.pan.suggestTooltip(Tooltip.ID.clickToCancelReplay);
    }
}
