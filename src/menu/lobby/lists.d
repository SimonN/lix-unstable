module menu.lobby.lists;

/* Extra UI elements that appear only in menu.lobby:
 * The list of players in the room, and the netplay color selector.
 */

import std.algorithm;
import std.conv;
import std.string;

import basics.globals;
import file.language;
import graphic.internal;
import gui;
import gui.picker.scrolist;
import net.structs;

class PeerButton : Button {
public:
    this(Geom g, in Profile prof)
    {
        assert (g.xlg > 2 * 20f);
        super(g);
        if (prof.feeling != Profile.Feeling.observing)
            addChild(new CutbitElement(new Geom(0, 0, 20, 20),
                getPanelInfoIcon(prof.style)));
        addChild(new Label(new Geom(20, 0, xlg - 40, 20), prof.name));
        auto check = new CutbitElement(new Geom(0, 0, 20, 20, From.RIGHT),
            InternalImage.menuCheckmark.toCutbit);
        check.xf = prof.feeling;
        addChild(check);
    }
}

class PeerList : ScrollableButtonList {
public:
    this(Geom g) { super(g); }

    void recreateButtonsFor(const(Profile[]) players)
    {
        Button[] array;
        foreach (profile; players)
            array ~= new PeerButton(newGeomForButton(), profile);
        replaceAllButtons(array);
    }
}

// ############################################################################

class RoomList : ScrollableButtonList {
private:
    // Button 0 is the make-new-room button, the room is generated by the
    // server. roomOfButtonNPlusOne[0] remembers where button 1 moves to,
    // roomOfButtonNPlusOne[1] remembers for botton 2, etc.
    const(Room)[] roomOfButtonNPlusOne;

public:
    this (Geom g) { super(g); }

    bool executeNewRoom() const
    {
        return buttons.length >= 1 && buttons[0].execute;
    }

    bool executeExistingRoom() const
    {
        return buttons.length >= 2 && buttons[1..$].any!(b => b.execute);
    }

    // You should only call this when execute() == true.
    // Returns the number of the room that (the player wants to move to).
    Room executeExistingRoomID() const
    {
        if (buttons.length < 2 || buttons[0].execute)
            return Room(0);
        assert (roomOfButtonNPlusOne.length + 1 == buttons.length);
        return roomOfButtonNPlusOne[buttons[1..$].countUntil!(b => b.execute)];
    }

    void clearButtons()
    {
        super.replaceAllButtons([]);
        roomOfButtonNPlusOne = [];
    }

    void recreateButtonsFor(const(Room[]) rooms, const(Profile[]) profiles)
    {
        Button[] array = [ new TextButton(newGeomForButton(),
                                          Lang.winLobbyRoomCreate.transl) ];
        for (int i = 0; i < rooms.length && i < profiles.length; ++i)
            array ~= new TextButton(newGeomForButton(), format!"%s: %s"(
                Lang.winLobbyRoomNumber.translf(rooms[i]), profiles[i].name));
        replaceAllButtons(array);
        roomOfButtonNPlusOne = rooms;
    }
}

// ############################################################################

private class ColorButton : BitmapButton {
    this(Geom g, Style st) { super(g, getPanelInfoIcon(st)); }
    override @property int yf() const { return 0; }
}

class ColorSelector : Element {
private:
    ColorButton[] _buttons;
    BitmapButton _spec;
    bool _execute;

public:
    this(Geom g)
    {
        super(g);
        foreach (int i; 0 .. styleToId(Style.max)) {
            _buttons ~= new ColorButton(new Geom(xlg/2f * (i % 2),
                ylg/5f * (i / 2), xlg/2f, ylg/5f), idToStyle(i));
            _buttons[$-1].xf = 1;
            addChild(_buttons[$-1]);
        }
        _spec = new BitmapButton(new Geom(0, 0, xlg, ylg/5f, From.BOTTOM),
            InternalImage.lobbySpec.toCutbit);
        addChild(_spec);
    }

    bool execute() const { return _execute; }
    @property bool observing() const { return _spec.on; }
    @property Style style() const
    {
        foreach (const size_t i, b; _buttons)
            if (b.on)
                return idToStyle(i.to!int);
        return idToStyle(0);
    }

    @property void setObserving()
    {
        _buttons.each!(b => b.on = false);
        _spec.on = true;
    }

    @property Style style(Style st)
    {
        foreach (const size_t i, b; _buttons)
            b.on = idToStyle(i.to!int) == st;
        _spec.on = false;
        return st;
    }

protected:
    override void calcSelf()
    {
        _execute = false;
        if (_spec.execute && ! observing) {
            setObserving();
            _execute = true;
        }
        foreach (const size_t i, b; _buttons)
            if (b.execute && ! b.on) {
                style = idToStyle(i.to!int);
                _execute = true;
            }
    }

private:
    Style idToStyle(int i) const { return to!Style(i + Style.red); }
    int styleToId(Style st) const { return st - Style.red; }
}
