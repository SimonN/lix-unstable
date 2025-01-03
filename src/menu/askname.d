module menu.askname;

import std.string;

static import file.option;

import basics.alleg5; // Explicit press of ESC
import file.key.key;
import file.language;
import file.option;
import file.trophy;
import gui;
import hardware.keyboard;
import menu.menubg;

class MenuAskName : MenuWithBackground {
private:
    bool _gotoMainMenu = false;
    bool _gotoExitApp = false;
    Texttype _tt;

public:
    const pure nothrow @safe @nogc {
        bool gotoMainMenu() { return _gotoMainMenu; }
        bool gotoExitApp() { return _gotoExitApp; }
    }

    this()
    {
        super(new Geom(0, 0, 200, 140, From.CENTER));
        super.windowTitle =  Lang.windowAskNameTitle.transl;

        addChild(new Label(new Geom(0, 40, this.xlg, 20, From.TOP),
            Lang.windowAskNameFirst.transl));
        addChild(new Label(new Geom(0, 60, this.xlg, 20, From.TOP),
            Lang.windowAskNameSecond.transl));

        _tt = new Texttype(new Geom(0, 100, this.xlg-40, 20, From.TOP));
        _tt.onEnter = () {
            if (_tt.text.strip.length > 0) {
                file.option.userNameOption = _tt.text.strip;
                _gotoMainMenu = true;
                // Main menu will change resolution for us.
                // I don't dare to do it here because we're in a GUI dialog.
            }
        };
        _tt.on = true;
        addChild(_tt);
    }

protected:
    // this is called even if the Window doesn't have focus
    override void workSelf()
    {
        if (! _gotoMainMenu && ! _gotoExitApp) {
            _tt.down = false;
            _tt.on = true;
            if (Key.byA5KeyId(ALLEGRO_KEY_ESCAPE).wasTapped) {
                _gotoExitApp = true;
            }
        }
    }
}
