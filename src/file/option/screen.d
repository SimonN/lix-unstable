module file.option.screen;

/*
 * The mutable screen options themselves are in file.option.allopts!
 *
 * This module (file.option.screen) merely has the enumerations
 * and convenience access functions for screen modes.
 */

import std.conv;

import file.option.allopts;

enum ScreenMode {
    windowed = 0,
    softwareFullscreen = 1,
    hardwareFullscreen = 2,
}

version (assert) {
    enum ScreenMode defaultScreenMode = ScreenMode.windowed;
}
else {
    enum ScreenMode defaultScreenMode = ScreenMode.softwareFullscreen;
}

struct DisplayTryMode {
    ScreenMode mode;
    int x, y;
}

@property DisplayTryMode displayTryMode() @system
{
    import std.stdio; // debugging
    writeln("");
    writeln("Entering displayTryMode");
    int dummy = 5;
    writeln("Local variable in this function sits at: ", cast(ulong) &dummy);

    writeln("screenMode = ", cast(ulong) cast(void*) screenMode);
    if (screenMode is null) {
        writeln("screenMode is null, we'll return software fullscreen");
        return DisplayTryMode(ScreenMode.softwareFullscreen, 0, 0);
    }
    else {
        writeln("screenMode is not null, continue");
    }

    writeln("screenMode.value = ", screenMode.value);
    if (screenMode.value == ScreenMode.softwareFullscreen) {
        writeln("screenMode.value == softw, we'll return software fullscreen");
        return DisplayTryMode(ScreenMode.softwareFullscreen, 0, 0);
    }
    else {
        writeln("screenMode is not software fullscreen, continue");
    }

    writeln("screenWindowedX = ", cast(ulong) cast(void*) screenWindowedX);
    if (screenWindowedX is null) {
        writeln("screenWindowedX is null, we'll return software fullscreen");
        return DisplayTryMode(ScreenMode.softwareFullscreen, 0, 0);
    }
    else {
        writeln("screenWindowedX is not null, continue");
    }

    writeln("screenWindowedY = ", cast(ulong) cast(void*) screenWindowedY);
    if (screenWindowedY is null) {
        writeln("screenWindowedY is null, we'll return software fullscreen");
        return DisplayTryMode(ScreenMode.softwareFullscreen, 0, 0);
    }
    else {
        writeln("screenWindowedY is not null, continue");
    }

    writeln("Final part of displayTryMode reached. We'll return:");
    writeln("Returning mode: ", userScreenModeOrDefault);
    writeln("Returning x: ", screenWindowedX.value);
    writeln("Returning y: ", screenWindowedY.value);
    writeln("Returning altogether: ", DisplayTryMode(userScreenModeOrDefault,
        screenWindowedX.value, screenWindowedY.value));
    return DisplayTryMode(userScreenModeOrDefault,
        screenWindowedX.value, screenWindowedY.value);
}

///////////////////////////////////////////////////////////////////////////////

private:

@property ScreenMode userScreenModeOrDefault()
{
    import std.stdio; // debugging
    writeln("Entering userScreenModeOrDefault");
    if (screenMode is null) {
        writeln("screenMode is null, returning: ", defaultScreenMode);
        return defaultScreenMode;
    }
    ScreenMode ret = defaultScreenMode;
    try {
        writeln("screenMode.value = ", screenMode.value);
        ret = screenMode.value.to!ScreenMode;
        writeln("screenMode.value = ", ret);
    }
    catch (Exception) {
        writeln("Conversion exception caught");
        ret = defaultScreenMode;
        screenMode.value = defaultScreenMode;
        writeln("screenMode.value was forcefully set to ", screenMode.value);
    }
    writeln("Returning from userScreenModeOrDefault: ", ret);
    return ret;
}
