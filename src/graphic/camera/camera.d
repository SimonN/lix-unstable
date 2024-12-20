module graphic.camera.camera;

/*
 * No hardware is queried here.
 * Pass all hardware readings (mouse, keyboard) into here.
 * Camera does not know about Torbit, only about Topology.
 */

import std.conv;
import std.math;

import basics.help;
import basics.topology;
import graphic.camera.camera1d;
import graphic.camera.zoom;

class Camera {
private:
    Zoom _zoom; // owned, created by ourself
    Camera1D _x;
    Camera1D _y;

public:
    this(in Topology source, in Point targetLen, in bool allowBlur)
    {
        _zoom = new Zoom(source, targetLen, allowBlur);
        _x = new Camera1D(source.xl, source.torusX, targetLen.x, _zoom);
        _y = new Camera1D(source.yl, source.torusY, targetLen.y, _zoom);
    }

    const pure nothrow @safe @nogc {
        Point targetLen() { return Point(_x.targetLen, _y.targetLen); }
        Point focus() { return Point(_x.focus, _y.focus); }
        final float zoom() { return _zoom.current; }

        bool mayScrollRight() { return _x.mayScrollHigher(); }
        bool mayScrollLeft()  { return _x.mayScrollLower(); }
        bool mayScrollDown()  { return _y.mayScrollHigher(); }
        bool mayScrollUp()    { return _y.mayScrollLower(); }
        bool prefersNearestNeighbor() { return _zoom.prefersNearestNeighbor; }

        Rect sourceSeen() { return Rect(_x.sourceSeen, _y.sourceSeen); }

        Rect sourceSeenBeforeFirstTorusSeam()
        {
            return Rect(
                _x.sourceSeenBeforeFirstTorusSeam,
                _y.sourceSeenBeforeFirstTorusSeam);
        }
    }

    final int divByZoomCeil(in float x) const pure nothrow @safe @nogc
    {
        return _zoom.divideCeil(x);
    }

    void focus(in Point p) nothrow pure @safe @nogc
    {
        _x.focus = p.x;
        _y.focus = p.y;
    }

    void zoomInKeepingTargetPointFixed(in Point targetToFix)
    {
        zoomKeepingTargetPointFixed(targetToFix, { _zoom.zoomIn(); });
    }

    void zoomOutKeepingTargetPointFixed(in Point targetToFix)
    {
        zoomKeepingTargetPointFixed(targetToFix, { _zoom.zoomOut(); });
    }

    void zoomOutToSeeEntireSource()
    {
        while (_zoom.zoomableOut
            && ! (_x.seesEntireSource && _y.seesEntireSource)
        ) {
            _zoom.zoomOut();
        }
        focus = focus;
    }

    void snapToBoundary()
    {
        _x.snapToBoundary();
        _y.snapToBoundary();
    }

    void copyZoomRoughlyFrom(in Camera other)
    {
        while (other.zoom > zoom && _zoom.zoomableIn) { _zoom.zoomIn(); }
        while (other.zoom < zoom && _zoom.zoomableOut) { _zoom.zoomOut(); }
    }

    /*
     * Input: A point on the target, as offset from top-left corner of target.
     *
     * Output: The point on the source that the camera, given its current
     * position and zoom, projects to the input point. The output point is
     * measured from the top-left corner of the source.
     *
     * This is a purely linear transformation. It doesn't cut off at the
     * source or target boundaries. If you ask what is far left of the screen,
     * you'll get source coordinates with far negative x.
     */
    Point sourceOf(in Point onTarget) const pure
    {
        return Point(_x.sourceOf(onTarget.x), _y.sourceOf(onTarget.y));
    }

private:
    void zoomKeepingTargetPointFixed(
        in Point targetToFix,
        void delegate() callZoom,
    ) {
        immutable Point oldSource = sourceOf(targetToFix);
        callZoom();
        immutable Point newSource = sourceOf(targetToFix);
        focus = focus + oldSource - newSource;
    }
}

unittest {
    Topology tp = new Topology(400, 300, false, false);
    Camera c = new Camera(tp, Point(80, 50), true);

    void assertCIsLikeAtStart(in string msg)
    {
        assert (c.zoom == 1f, msg ~ ", zoom");
        assert (c.sourceSeen == Rect(160, 125, 80, 50));
        assert (c.sourceOf(Point(0, 0)) == Point(160, 125),
            msg ~ ", sourceOf(0)=" ~ c.sourceOf(Point(0, 0)).to!string);
        assert (c.focus == Point(200, 150), msg ~ " should focus on center");
    }
}
