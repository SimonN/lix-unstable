module editor.gui.constant;

import file.option;
import basics.globals;
import editor.gui.okcancel;
import file.language;
import graphic.color;
import gui;
import level.level;

class ConstantsWindow : OkCancelWindow {
private:
    TextWithWarning _title;
    TextWithWarning _author;
    NumPick _intendedNumberOfPlayers;
    NumPick _initial;
    NumPick _spawnint;
    NumPick _required;
    NumPick _overtime;
    Label _requiredLabel;
    Label _overtimeLabel;

public:
    this(Level level)
    {
        enum thisXl = 450f;
        super(new Geom(0, 0, thisXl, 240, From.CENTER),
            Lang.winConstantsTitle.transl);
        enum butX   = 140f;
        enum butXl  = thisXl - butX - 20f;

        Label label(in float y, in Lang cap)
        {
            Label l = new Label(new Geom(
                20, y, TextWithWarning.captionXl, 20), cap.transl);
            addChild(l);
            return l;
        }
        label(110, Lang.winConstantsPlayers);
        label(140, Lang.winConstantsInitial);
        label(200, Lang.winConstantsSpawnint);
        _requiredLabel = label(180, Lang.winConstantsRequired);
        _overtimeLabel = label(180, Lang.winConstantsOvertime);

        _title = new TextWithWarning(
            new Geom(20, 25, xlg - 40, 35),
            Lang.winConstantsLevelName,
            level.md.nameEnglish);
        _author = new TextWithWarning(
            new Geom(20, 60, xlg - 40, 35),
            Lang.winConstantsAuthor,
            level.author);

        NumPickConfig cfg;
        cfg.digits = 4;
        cfg.stepMedium = 3;
        cfg.min = 1;
        cfg.max = basics.globals.teamsPerLevelMax;
        _intendedNumberOfPlayers = new NumPick(new Geom(butX + 20, 110,
                                                        130, 20), cfg);
        _intendedNumberOfPlayers.number = level.intendedNumberOfPlayers;

        cfg.sixButtons = true;
        cfg.stepMedium = 10;
        cfg.max = Level.initialMax;
        _initial  = new NumPick(new Geom(butX, 140, 170, 20), cfg);
        _required = new NumPick(new Geom(butX, 170, 170, 20), cfg);
        _initial .number = level.initial;
        _required.number = level.required;

        cfg.sixButtons = false;
        cfg.max = Level.spawnintMax;
        _spawnint = new NumPick(new Geom(butX + 20, 200, 130, 20), cfg);
        _spawnint.number = level.spawnint;

        cfg.sixButtons = true;
        cfg.time = true;
        cfg.stepBig = 60;
        cfg.max = 60*9;
        cfg.min = 0;
        _overtime = new NumPick(new Geom(_required.geom), cfg);
        _overtime.number = level.overtimeSeconds;

        addChildren(_title, _author, _intendedNumberOfPlayers,
                    _initial, _spawnint, _required, _overtime);
        showOrHideModalFields();
    }

protected:
    override void selfWriteChangesTo(Level level)
    {
        level.md.nameEnglish = _title.text;
        level.md.author = _author.text;
        level.intendedNumberOfPlayers = _intendedNumberOfPlayers.number;
        level.md.initial = _initial.number;
        level.md.required = _required.number;
        level.spawnint = _spawnint.number;
        level.overtimeSeconds = _overtime.number;
    }

    override void calcSelf() { showOrHideModalFields(); }

    void showOrHideModalFields()
    {
        immutable bool multi = _intendedNumberOfPlayers.number > 1;
        _required.shown = ! multi;
        _requiredLabel.shown = ! multi;
        _overtime.shown = multi;
        _overtimeLabel.shown = multi;
    }
}

private:

class TextWithWarning : Element {
private:
    Label _caption;
    WarningText _warning;
    Texttype _texttype;

public:
    enum captionXl = 120f;

    this(Geom g, in Lang cap, in string typedTextAtStart)
    {
        super(g);
        _caption = new Label(new Geom(
            0, 0, captionXl, 20, From.BOTTOM_LEFT), cap.transl);
        addChild(_caption);

        immutable float warnYlg = ylg - 20f;
        immutable float warnPad = (warnYlg - 10f) / 2;
        _warning = new WarningText(new Geom(
            captionXl,
            warnPad,
            xlg - captionXl, warnYlg - 2 * warnPad, From.TOP_LEFT));
        _warning.hide;
        addChild(_warning);

        _texttype = new Texttype(new Geom(
            0, 0, xlg - captionXl, 20, From.BOTTOM_RIGHT));
        _texttype.allowScrolling = true;
        _texttype.text = typedTextAtStart;
        addChild(_texttype);
    }

    string text() const pure nothrow @safe @nogc
    {
        return _texttype.text;
    }

protected:
    override void workSelf()
    {
        _warning.shown = textWouldAbbreviateInBrowser;
    }

private:
    bool textWouldAbbreviateInBrowser() const nothrow @safe
    {
        immutable biggestFittingTitle = "Any Way You Want mmmmmmmki";
        // We abuse _caption here because its font is _texttype's font.
        return _caption.textRenderedXlg(_texttype.text)
            >  _caption.textRenderedXlg(biggestFittingTitle);
    }
}

class WarningText : Element {
private:
    Label _red;
    Label _desc;

public:
    this(Geom g)
    {
        super(g);
        _red = new Label(new Geom(0, 0, xlg, ylg),
            Lang.winConstantsTooLongWarn.transl);
        _red.font = djvuS;
        _red.color = color.guiTextWarning;
        addChild(_red);

        immutable float nextXg = _red.textRenderedXlg + 4f;
        _desc = new Label(new Geom(nextXg, 0, xlg - nextXg),
            Lang.winConstantsTooLongDesc.transl);
        _desc.font = djvuS;
        addChild(_desc);
    }
}
