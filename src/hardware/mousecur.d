module hardware.mousecur;

/*
 * This is only for the drawable mouse cursor.
 *
 * To read mouse input, look at the module hardware.mouse instead.
 *
 * There are two graphic objects: The main cursor and the sidekick graphic.
 * The sidekick graphic exists throughout, even if it's usually in its
 * empty frame (0, 0).
 */

import basics.rect;
import file.log;
import graphic.cutbit;
import graphic.internal;
import graphic.graphic;
import hardware.mouse;

public MouseCursor mouseCursor;

struct MouseCursor {
private:
    Graphic _mainCursor; // null iff MouseCursor not initialized
    Graphic _sideCursor; // null iff MouseCursor not initialized
    Shape _shape;
    Arrows _arrows;
    Sidekick _sidekick;

public:
    enum Shape : int {
        crosshair,
        openSquare,
        trashcan,
        scissors,
    }

    enum Arrows : int {
        none,
        left,
        right,
        scroll,
    }

    enum Sidekick : int {
        none,
        scissors,
        insert,
    }

    void initialize()
    in { assert (_mainCursor is null, "mouse cursor is already initialized"); }
    out { assert (_mainCursor !is null); }
    do {
        _mainCursor = makeCursor(InternalImage.mouseMain, "Main");
        _sideCursor = makeCursor(InternalImage.mouseSidekick, "Sidekick");
    }

    void deinitialize()
    {
        this = MouseCursor();
    }

    void want(in Shape s) pure nothrow @safe @nogc { _shape = s; }
    void want(in Arrows a) pure nothrow @safe @nogc { _arrows = a; }
    void want(in Sidekick s) pure nothrow @safe @nogc { _sidekick = s; }

    void wantPlainCrosshair() pure nothrow @safe @nogc
    {
        want(Shape.crosshair);
        want(Arrows.none);
        want(Sidekick.none);
    }

    void draw()
    {
        assert (_mainCursor,
            "Call mouseCursor.initialize() before drawing");
        _mainCursor.xf = mainXf();
        _mainCursor.yf = mainYf();
        _mainCursor.loc = Point(hardware.mouse.mouseX - _mainCursor.xl/2 + 1,
                                hardware.mouse.mouseY - _mainCursor.yl/2 + 1);
        _mainCursor.drawToCurrentAlbitNotTorbit();

        _sideCursor.xf = _sidekick;
        _sideCursor.loc = _mainCursor.loc + _mainCursor.len
                        + Point(1, -_sideCursor.yl);
        _sideCursor.drawToCurrentAlbitNotTorbit();
    }

private:
    Graphic makeCursor(in InternalImage id, in string nameForLogging)
    {
        const(Cutbit) cb = id.toCutbit;
        if (! cb.valid) {
            logf("%s mouse cursor not found: %s",
                nameForLogging, id.toLoggableName);
        }
        return new Graphic(cb, null);
    }

    int mainXf() const pure nothrow @safe @nogc
    {
        final switch (_shape) {
            case Shape.crosshair: return _arrows;
            case Shape.openSquare: return _arrows;
            case Shape.trashcan: return 1;
            case Shape.scissors: return _arrows;
        }
    }

    int mainYf() const pure nothrow @safe @nogc
    {
        return _shape; // Happens to work. Change to switch (_shape) if not.
    }
}
