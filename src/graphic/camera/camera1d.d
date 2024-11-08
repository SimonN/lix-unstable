module graphic.camera.camera1d;

import std.algorithm;
import std.conv;
import std.math;

import basics.help;
import basics.rect; // Side
import graphic.camera.zoom;

class Camera1D {
private:
    const(Zoom) _zoomOwnedBy2DCamera;

    /*
     * The point of the source Torbit that will be blit to the center
     * of the target. Also determines whether we can still scroll further.
     * Always in [0, sourceLen[.
     */
    int _focus;

public:
    /*
     * Number of pixels in the entire source Torbit. We will often copy
     * fewer than this to the target with the deeper zooms.
     * (sourceLen) and (torus) together describe one dimension of the
     * source Torbit.
     */
    immutable int sourceLen;
    immutable bool torus;

    /* Number of pixels in the target canvas. */
    immutable int targetLen;

public:
    this(
        in int aSourceLen,
        in bool aTorus,
        in int aTargetLen,
        const(Zoom) aZoom,
    ) in {
        assert (aSourceLen > 0, "Camera1D: source len must be > 0");
        assert (aTargetLen > 0, "Camera1D: target len must be > 0");
    }
    do {
        _zoomOwnedBy2DCamera = aZoom;
        targetLen = aTargetLen;
        sourceLen = aSourceLen;
        torus = aTorus;
        scrollToCenter();
    }

pure nothrow @safe @nogc:
    int focus() const { return _focus; }

    void scrollToCenter() { _focus = sourceLen / 2; }

    void scrollTo(in int aFocus)
    {
        _focus = torus ? basics.help.positiveMod(aFocus, sourceLen)
            : clamp(aFocus, focusHardMin, focusHardMax);
    }

    // On non-torus maps, we want the initial scrolling position exactly at the
    // boundary, or a good chunk away from the boundary.
    void snapToBoundary()
    {
        if (torus)
            return;
        immutable int margin = focusSoftMin / 6;
        if (2 * focus < focusSoftMin + focusSoftMax
            && focus < focusSoftMin + margin
        ) {
            scrollTo(focusSoftMin);
        }
        else if (focus > focusSoftMax - margin) {
            scrollTo(focusSoftMax);
        }
    }

const pure nothrow @safe @nogc:
    bool mayScrollHigher() { return _focus < focusHardMax || torus; }
    bool mayScrollLower()  { return _focus > focusHardMin || torus; }
    bool seesEntireSource() { return numPixelsSeen >= sourceLen; }

    Side sourceSeen()
    out (side) {
        assert (side.len >= 0);
    } do {
        immutable int first = focus - numPixelsSeen / 2;
        immutable int start = torus ? positiveMod(first, sourceLen) : first;
        return Side(start, numPixelsSeen);
    }

    /*
     * The rectangle never wraps over a torus seam, but instead is cut off.
     * Callers who what to draw a full screen rectangle must compute the
     * remainder behind the seam themselves.
     * This is bad design, Camera1D should compute the remainder.
     */
    Side sourceSeenBeforeFirstTorusSeam()
    out (side) {
        assert (side.len >= 0);
    } do {
        immutable Side uncut = sourceSeen;
        return Side(uncut.start, min(uncut.len, sourceLen - uncut.start));
    }

    /*
     * Input: Coordinate on the target, offset from its lower end.
     * Output: The coordinate of the source that projects there.
     * A purely linear transformation, no cutting at source boundaries.
     */
    int sourceOf(in int pixelOnTarget)
    {
        immutable int ret = _zoomOwnedBy2DCamera.divideFloor(pixelOnTarget)
            + sourceSeen.start;
        return torus ? positiveMod(ret, sourceLen) : ret;
    }

private:
    /*
     * softMin/Max: You can scroll further than this by zooming in/out,
     *      but hold-to-scroll or edge scrolling can't scroll past soft limits.
     *
     * hardMin/Max: We clamp all repositioning to the hard limits.
     *      It's a program invariant to always have _focus within hard limits.
     */
    int focusHardMin() { return 0; }
    int focusHardMax() { return sourceLen; }

    int focusSoftMin()
    {
        return min(numPixelsSeen / 2, sourceLen / 2);
    }

    int focusSoftMax()
    {
        return max(sourceLen - numPixelsSeen + numPixelsSeen / 2,
            sourceLen / 2);
    }

    /*
     * numPixelsSeen: Number of pixels from the source that are copied.
     * With deep zoom, (large value zoom()), then this is small.
     * Zoomed out, this might be more than the source.
     */
    int numPixelsSeen() {
        return _zoomOwnedBy2DCamera.divideCeil(targetLen);
    }
}
