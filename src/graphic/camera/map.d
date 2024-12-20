module graphic.camera.mapncam;

/*
 * class Map has a camera pointing somewhere inside the entire
 * torbit. The camera specifies the center of a rectangle.
 */

import std.algorithm;
import std.conv;
import std.math;
import std.range;

import enumap;

import basics.alleg5 : al_draw_filled_rectangle, al_draw_bitmap_region,
                       al_draw_scaled_bitmap, Albit;
import basics.help;
import basics.topology;
import opt = file.option.allopts;
import graphic.camera.camera;
import graphic.camera.zoom;
import graphic.color;
import graphic.torbit;

static import hardware.display;
static import hardware.keyboard;
static import hardware.mouse;

class MapAndCamera {
private:
    Point _scrollGrabbed;
    bool _isHoldScrolling;
    bool _suggestTooltip;

    Enumap!(CamSize, Camera) _cams;
    CamSize _chosenCam = CamSize.fullWidth;

    // We have two ground torbits, because we must choose at their creation
    // whether we want nearest-neighbor scaling or blurry linear interpolation.
    Torbit _nearestNeighbor;
    Torbit _blurryScaling;

public:
    enum CamSize : bool { fullWidth, withTweaker }

    /*
     * Deduct from the real screen xl/yl the GUI elements' yl, then pass the
     * remainder to this constructor.
     */
    this(
        in Topology topolOfSource,
        in Enumap!(CamSize, Point) targetSizes
    ) {
        foreach (key, val; targetSizes) {
            _cams[key] = new Camera(topolOfSource, val,
                opt.allowBlurryZoom.value);
        }
        auto cfg = Torbit.Cfg(topolOfSource);
        _nearestNeighbor = new Torbit(cfg);
        cfg.smoothlyScalable = true;
        _blurryScaling = new Torbit(cfg);
    }

    void dispose()
    {
        if (_nearestNeighbor) {
            _nearestNeighbor.dispose();
            _nearestNeighbor = null;
        }
        if (_blurryScaling) {
            _blurryScaling.dispose();
            _blurryScaling = null;
        }
    }

    const pure {
        bool scrollable()
        {
            const c = chosenCam();
            return c.mayScrollUp() || c.mayScrollDown()
                || c.mayScrollLeft() || c.mayScrollRight();
        }
        bool isHoldScrolling() { return _isHoldScrolling; }
        bool suggestHoldScrollingTooltip() { return _suggestTooltip; }
        float zoom() { return chosenCam.zoom; }
    }

    const(Topology) topology() const pure nothrow @safe @nogc
    {
        return torbit;
    }

    inout(Torbit) torbit() inout pure nothrow @safe @nogc
    {
        assert (_nearestNeighbor);
        assert (_blurryScaling);
        return chosenCam.prefersNearestNeighbor
            ? _nearestNeighbor : _blurryScaling;
    }

// This function shall intercept calls to Torbit.resize.
void resize(in int newXl, in int newYl)
{
    if (topology.xl == newXl && topology.yl == newYl) {
        // the Torbits would get no-op calls, but we shouldn't reset zoom.
        return;
    }
    _nearestNeighbor.resize(newXl, newYl);
    _blurryScaling.resize(newXl, newYl);
    reinitializeCamera();
}

// This function shall intercept calls to Torbit.setTorusXY.
void setTorusXY(in bool aTx, in bool aTy)
{
    if (torbit.torusX == aTx && torbit.torusY == aTy)
        return;
    _nearestNeighbor.setTorusXY(aTx, aTy);
    _blurryScaling.setTorusXY(aTx, aTy);
    reinitializeCamera();
}

private void reinitializeCamera()
{
    foreach (key, oldCam; _cams) {
        immutable Point oldFocus = oldCam.focus;
        _cams[key] = new Camera(torbit, oldCam.targetLen,
            opt.allowBlurryZoom.value);
        _cams[key].scrollTo(oldFocus);
    }
}

    void choose(in CamSize next)
    {
        if (next == _chosenCam) {
            return;
        }
        _cams[next].copyZoomRoughlyFrom(chosenCam);
        /*
         * Refocus (= choose camera's center land point) so that many land
         * pixels stay where they were on screen using the old camera.
         * Hardcoding Point(0, 0) assumes that the tweaker is on the right.
         */
        _cams[next].scrollTo(chosenCam.focus);
        immutable topLeftLand = chosenCam.sourceOf(Point(0, 0));
        immutable topLeftWrong = _cams[next].sourceOf(Point(0, 0));
        _cams[next].scrollTo(_cams[next].focus - (topLeftWrong - topLeftLand));
        _chosenCam = next;
    }

    private inout(Camera) chosenCam() inout pure nothrow @safe @nogc
    {
        return _cams[_chosenCam];
    }

void centerOnAverage(Rx, Ry)(Rx rangeX, Ry rangeY)
    if (isInputRange!Rx && isInputRange!Ry)
{
    chosenCam.scrollTo(Point(
        topology.torusAverageX(rangeX),
        topology.torusAverageY(rangeY)));
}

void zoomOutToSeeEntireMap() { chosenCam.zoomOutToSeeEntireSource(); }
void snapToBoundary() { chosenCam.snapToBoundary(); }

Point mouseOnTarget() const
{
    return hardware.mouse.mouseOnScreen;
}

Point mouseOnLand() const
{
    return chosenCam.sourceOf(mouseOnTarget);
}

void calcZoomAndScrolling()
{
    if (opt.keyZoomIn.wasTappedOrRepeated) {
        chosenCam.zoomInKeepingTargetPointFixed(mouseOnTarget);
    }
    if (opt.keyZoomOut.wasTappedOrRepeated) {
        chosenCam.zoomOutKeepingTargetPointFixed(mouseOnTarget);
    }
    calcEdgeScrolling(chosenCam);
    calcHoldScrolling(chosenCam);
}

private void calcEdgeScrolling(Camera cam)
{
    _suggestTooltip = false;
    if (! scrollable || ! hardware.mouse.hardwareMouseInsideWindow
        || opt.scrollSpeedEdge.value <= 0)
        return;

    float scrd = opt.scrollSpeedEdge.value;
    if (hardware.mouse.mouseHeldRight())
        scrd *= 4;
    scrd /= zoom;
    if (scrd < 1)
        scrd = 1;
    immutable dxl = hardware.display.displayXl - 1;
    immutable dyl = hardware.display.displayYl - 1;
    immutable int a = scrd.roundInt;
    void msg(bool b) { _suggestTooltip = _suggestTooltip || b; }

    with (hardware.mouse) {
        .Point mov = .Point(0, 0);
        // Deliberately, we suggest the tooltip when we could scroll into
        // the opposite direction, not into the scrolling direction. The idea
        // is that I don't want the tooltip at the bottom edge when you can't
        // scroll down, but tooltip should persist after scrolled all the way.
        if (mouseX == 0)   { mov -= .Point(a, 0); msg(cam.mayScrollRight); }
        if (mouseX == dxl) { mov += .Point(a, 0); msg(cam.mayScrollLeft); }
        if (mouseY == 0)   { mov -= .Point(0, a); msg(cam.mayScrollDown); }
        if (mouseY == dyl) { mov += .Point(0, a); msg(cam.mayScrollUp); }
        cam.scrollTo(cam.focus + mov);
    }
}

private void calcHoldScrolling(Camera cam)
{
    if (! scrollable) {
        _isHoldScrolling = false;
        return;
    }
    if (opt.keyScroll.isHeld && ! _isHoldScrolling) {
        // first frame of scrolling
        _scrollGrabbed = hardware.mouse.mouseOnScreen;
    }
    _isHoldScrolling = opt.keyScroll.isHeld;
    if (! _isHoldScrolling)
        return;

    int clickScrollingOneDimension(in bool minus, in bool plus,
        in int grabbed, in int mouse, in int mickey,
        void function() freeze
    ) {
        immutable dir = opt.holdToScrollInvert.value ? -1 : 1;
        immutable uninvertedScrollingAllowed =
               (minus && mouse <= grabbed && mickey < 0)
            || (plus  && mouse >= grabbed && mickey > 0);
        if (dir == 1 && uninvertedScrollingAllowed
            || dir == -1 && (plus || minus)
        ) {
            immutable ret = roundInt(mickey * opt.holdToScrollSpeed.value
                    * dir / zoom / 4); // the factor /4 comes from C++ Lix
            freeze();
            return ret;
        }
        return 0;
    }
    immutable p = Point(
        clickScrollingOneDimension(cam.mayScrollLeft, cam.mayScrollRight,
        _scrollGrabbed.x, hardware.mouse.mouseX,
        hardware.mouse.mouseMickey.x, &hardware.mouse.freezeMouseX)
        ,
        clickScrollingOneDimension(cam.mayScrollUp, cam.mayScrollDown,
        _scrollGrabbed.y, hardware.mouse.mouseY,
        hardware.mouse.mouseMickey.y, &hardware.mouse.freezeMouseY));
    cam.scrollTo(cam.focus + p);
}



// ############################################################################
// ########################################################### drawing routines
// ############################################################################



void drawCamera()
{
    // Draw the void.
    al_draw_filled_rectangle(0, 0, chosenCam.targetLen.x,
        chosenCam.targetLen.y, color.screenBorder);

    drawCameraBorderless(chosenCam);
}

// Draw camera (maybe several times next to itself)
// to the current drawing target, most likely the screen
private void drawCameraBorderless(in Camera cam)
{
    immutable int overallMaxX = cam.targetLen.x;
    immutable int overallMaxY = cam.targetLen.y;
    immutable bool torX = topology.torusX;
    immutable bool torY = topology.torusY;
    immutable int plusX = (topology.xl * zoom).ceil.to!int;
    immutable int plusY = (topology.yl * zoom).ceil.to!int;
    for (int x = 0; x < overallMaxX; x += plusX) {
        for (int y = 0; y < overallMaxY; y += plusY) {
            // 4th and 5th arg are the size of the image to be drawn
            // in this iteration of the double-for loop. This should always
            // be as much as possible, i.e., the first argument to min().
            // Only in the last iteration of the loop,
            // a smaller rectangle is better.
            drawCamera_with_target_corner(cam, x, y,
                torX ? min(plusX, overallMaxX - x) : overallMaxX,
                torY ? min(plusY, overallMaxY - y) : overallMaxY);
            if (! topology.torusY) break;
        }
        if (! topology.torusX) break;
    }
}

private void
drawCamera_with_target_corner(
    in Camera cam,
    in int tcx, // x coordinate of target corner
    in int tcy,
    in int maxTcxl, // length, away from (tcx, tcy). Draw at most this much
    in int maxTcyl  // to the target.
) {
    immutable Rect r = cam.sourceSeenBeforeFirstTorusSeam();
    // Source length of the non-wrapped portion. (Target len = this * zoom.)
    immutable sxl1 = min(r.xl, cam.divByZoomCeil(maxTcxl));
    immutable syl1 = min(r.yl, cam.divByZoomCeil(maxTcyl));
    // target corner coordinates and size of the wrapped-around torus portion
    immutable tcx2 = tcx + r.xl * zoom;
    immutable tcy2 = tcy + r.yl * zoom;
    // source length of the wrapped-around torus portion
    immutable sxl2 = min(cam.sourceSeen.xl - r.xl,
                         cam.divByZoomCeil(maxTcxl) - sxl1);
    immutable syl2 = min(cam.sourceSeen.yl - r.yl,
                         cam.divByZoomCeil(maxTcyl) - syl1);

    void blitOnce(in int sx,  in int sy,  // source x, y
                  in int sxl, in int syl, // length on the source
                  in float tx, in float ty)  // start of the target
    {
        if (zoom == 1)
            al_draw_bitmap_region(torbit.albit, sx, sy, sxl, syl, tx, ty, 0);
        else
            al_draw_scaled_bitmap(torbit.albit, sx, sy, sxl, syl,
                                  tx, ty, zoom * sxl, zoom * syl, 0);
    }
    immutable drtx = topology.torusX && sxl2 > 0;
    immutable drty = topology.torusY && syl2 > 0;
                      blitOnce(r.x, r.y, sxl1, syl1, tcx,  tcy);
    if (drtx        ) blitOnce(0,   r.y, sxl2, syl1, tcx2, tcy);
    if (        drty) blitOnce(r.x, 0,   sxl1, syl2, tcx,  tcy2);
    if (drtx && drty) blitOnce(0,   0,   sxl2, syl2, tcx2, tcy2);
}

    void loadCameraRect(in Torbit src)
    {
        loadCameraRectImpl(src, torbit, chosenCam);
    }

    void clearSourceThatWouldBeBlitToTarget(Alcol col)
    {
        torbit.drawFilledRectangle(chosenCam.sourceSeen, col);
    }

}
// end class Map

private:

void loadCameraRectImpl(in Torbit src, Torbit target, in Camera cam)
{
    assert (src.albit);
    assert (target.xl == src.xl);
    assert (target.yl == src.yl);

    // We don't use a drawing delegate with the Torbit base cless.
    // That would be like stamping the thing 4x entirelly onto the torbit.
    // We might want to copy less than 4 entire stamps. Let's implement it.
    immutable Rect r = cam.sourceSeenBeforeFirstTorusSeam();

    immutable bool drtx = target.torusX && r.xl < cam.sourceSeen.xl;
    immutable bool drty = target.torusY && r.yl < cam.sourceSeen.yl;

    auto targetTorbit = TargetTorbit(target);
    if (opt.paintTorusSeams.value) {
        drawTorusSeams(target);
    }
    void drawHere(int ax, int ay, int axl, int ayl)
    {
        al_draw_bitmap_region(cast (Albit) (src.albit),
            ax, ay, axl, ayl, ax, ay, 0);
    }
    if (true        ) drawHere(r.x, r.y, r.xl, r.yl);
    if (drtx        ) drawHere(0,   r.y, cam.sourceSeen.xl - r.xl, r.yl);
    if (        drty) drawHere(r.x, 0,   r.xl, cam.sourceSeen.xl - r.yl);
    if (drtx && drty) drawHere(0,   0,   cam.sourceSeen.xl - r.xl,
                                         cam.sourceSeen.yl - r.yl);
}

void drawTorusSeams(Torbit target) { with (target)
{
    // We assume that target is already TargetTorbit.
    if (torusX) {
        al_draw_filled_rectangle(xl - 1, 0, xl, yl, color.torusSeamL);
        al_draw_filled_rectangle(0,      0, 1,  yl, color.torusSeamD);
    }
    if (torusY) {
        al_draw_filled_rectangle(0, yl - 1, xl, yl, color.torusSeamL);
        al_draw_filled_rectangle(0, 0,      xl, 1,  color.torusSeamD);
    }
    if (torusX && torusY)
        al_draw_filled_rectangle(xl - 1, 0, xl, 1, color.torusSeamL);
}}
