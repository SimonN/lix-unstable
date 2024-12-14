module hardware.keyboard;

/* Important for the main loop:
 * Phyu mouse first, then keyboard. During updating the keyboard, we read
 * the keyboard by Allegro 5, and also the mouse by hardware.mouse.
 * Mouse buttons may be mapped as hotkeys.
 */

import std.algorithm;
import std.array;
import std.utf;

import basics.alleg5;
import file.key.key;
import file.key.set;
import file.log;
import hardware.keyhist;
import hardware.mouse;

static import basics.globals;

bool wasTapped(in KeySet set) nothrow @safe @nogc
{
    return set[].any!(k => statsFor(k).wasTapped);
}

bool isHeld(in KeySet set) nothrow @safe @nogc
{
    return set[].any!(k => statsFor(k).isHeldForAlticks > 0);
}

bool wasReleased(in KeySet set) nothrow @safe @nogc
{
    return set[].any!(k => statsFor(k).wasReleased);
}

bool wasTappedOrRepeated(in KeySet set) nothrow @safe @nogc
{
    return set[].any!(k => statsFor(k).wasTappedOrRepeated);
}

bool backspace() nothrow @safe @nogc
{
    return _backspace;
}

bool ctrlHeld() nothrow @safe @nogc
{
    return eitherIsHeld(ALLEGRO_KEY_LCTRL, ALLEGRO_KEY_RCTRL);
}

bool shiftHeld() nothrow @safe @nogc
{
    return eitherIsHeld(ALLEGRO_KEY_LSHIFT, ALLEGRO_KEY_RSHIFT);
}

bool altHeld() nothrow @safe @nogc
{
    return eitherIsHeld(ALLEGRO_KEY_ALT, ALLEGRO_KEY_ALTGR);
}

Key whatExactlyWasTapped() nothrow @safe @nogc // For the hotkey-mapping button
{
    foreach (int id, ref KeyHistory hist; _kbHist) {
        if (hist.wasTapped) {
            return Key.allegroKeyId(id);
        }
    }
    foreach (int id, ref KeyHistory hist; _mbHist) {
        if (hist.wasTapped) {
            return Key.mouseButtonId(id);
        }
    }
    if (_whHist[0].wasTapped) {
        return Key.wheelUp;
    }
    if (_whHist[1].wasTapped) {
        return Key.wheelDown;
    }

    static assert (! Key.init.isValid);
    return Key.init;
}

void clearKeyBufferAfterAltTab() nothrow @safe @nogc
{
    foreach (ref stat; _kbHist) stat.wasTapped = false;
    foreach (ref stat; _mbHist) stat.wasTapped = false;
    foreach (ref stat; _whHist) stat.wasTapped = false;
}

// Take great care to not introduce malformed UTF8, even though we build
// _bufferUTF8 already only by encoing codepoints with the D standard lib.
string utf8Input() nothrow
{
    try {
        std.utf.validate(_bufferUTF8);
        return _bufferUTF8;
    }
    catch (Exception) {
        import std.format;
        import std.conv;

        string ints;
        // Prevent autodecoding by explicit array indexing.
        // Don't use _bufferUTF8 as a range or foreach here.
        for (int i = 0; i < _bufferUTF8.length; ++i) {
            try
                ints ~= format!" %2x"(_bufferUTF8[i].to!ubyte);
            catch (Exception)
                ints ~= " ??";
        }
        logf("Bad UTF-8 keyboard input:%s", ints); // yes, no space before %s
        _bufferUTF8 = "";
        return "";
    }
}

void initialize()
{
    al_install_keyboard();
    _queue = al_create_event_queue();
    assert (_queue);
    al_register_event_source(_queue, al_get_keyboard_event_source());
}

void deinitialize()
{
    if (_queue) {
        al_unregister_event_source(_queue, al_get_keyboard_event_source());
        al_destroy_event_queue(_queue);
        _queue = null;
        al_uninstall_keyboard();
    }
}

void calcCallThisAfterMouseCalc()
{
    foreach (ref stat; _kbHist) stat.resetTappedAndReleased;
    _bufferUTF8 = null;
    _backspace  = false;

    fetchStatsFromAllegro();
    foreach (ref stat; _kbHist) {
        stat.updateHeldAccordingToTapped();
    }

    _kbHist[ALLEGRO_KEY_ENTER].mergeWith(_kbHist[ALLEGRO_KEY_PAD_ENTER]);
}

// ############################################################################
private: // ########################################################## :private
// ############################################################################

ALLEGRO_EVENT_QUEUE* _queue;
bool _backspace;
string _bufferUTF8;
KeyHistory[ALLEGRO_KEY_MAX] _kbHist;

const(KeyHistory) statsFor(in Key k) nothrow @safe @nogc
{
    final switch (k.type) {
        case Key.Type.keyboardKey: return _kbHist[k.keyboardKey];
        case Key.Type.mouseButton: return _mbHist[k.mouseButton];
        case Key.Type.mouseWheelDirection:
            return _whHist[k == Key.wheelUp ? 0 : 1];
    }
}

bool eitherIsHeld(in int idA, in int idB) nothrow @safe @nogc
{
    return _kbHist[idA].isHeldForAlticks > 0
        || _kbHist[idB].isHeldForAlticks > 0;
}

void fetchStatsFromAllegro()
{
    ALLEGRO_EVENT event;
    while(al_get_next_event(_queue, &event))
    {
        if (event.type == ALLEGRO_EVENT_KEY_DOWN) {
            _kbHist[event.keyboard.keycode].wasTapped = true;
        }
        else if (event.type == ALLEGRO_EVENT_KEY_UP) {
            _kbHist[event.keyboard.keycode].wasReleased = true;
        }
        else if (event.type == ALLEGRO_EVENT_KEY_CHAR) {
            immutable int c = event.keyboard.unichar;
            if ((c < 0 || c >= 0x20) // ignore nonprintable ASCII controls
                && c != 0x7F  // ignore the delete character
                && ! ctrlHeld // Ctrl+V shall not type 'v'
            ) {
                char[4] buf;
                auto bytesUsed = std.utf.encode(buf, c);
                _bufferUTF8 ~= buf[0 .. bytesUsed];
            }
            else if (event.keyboard.keycode == ALLEGRO_KEY_BACKSPACE) {
                // A5 manual tells us to do this outside of the UTF8 scanning
                _backspace = true;
            }
        }
    }
}
