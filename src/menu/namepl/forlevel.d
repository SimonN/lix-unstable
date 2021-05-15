module menu.namepl.forlevel;

import std.algorithm;
import std.format;
import std.range;

import optional;

import graphic.color;
import file.language;
import level.level;
import menu.namepl.base;
import gui;

class Nameplate : Element, PreviewLevelOrReplay {
private:
    LevelNameplate _level;
    ReplayNameplate _replay;

public:
    this(Geom g)
    {
        super(g);
        _level = new LevelNameplate(new Geom(0, 0, xlg, ylg));
        _replay = new ReplayNameplate(new Geom(0, 0, xlg, ylg));
        addChildren(_level, _replay);
    }

    void previewNone()
    {
        _level.hide();
        _replay.hide();
    }

    void preview(in Level lev)
    {
        _level.preview(lev);
        _replay.hide();
    }

    void preview(in Replay rep, in Level lev)
    {
        _level.hide();
        _replay.preview(rep, lev);
    }
}

private:

class LevelNameplate : Element {
private:
    Label _title;
    LabelTwo _by;
    LabelTwo _save;

public:
    this(Geom g)
    in {
        assert (geom.ylg >= 60f);
    }
    body {
        super(g);
        _title = new Label(new Geom(0, 0, xlg, 20));
        _title.undrawBeforeDraw = true;
        _by = new LabelTwo(new Geom(0, 20, xlg, 20),
            Lang.browserInfoAuthor.transl);
        _save = new LabelTwo(new Geom(0, 40, xlg, 20),
            Lang.browserInfoInitgoal.transl);
        addChildren(_title, _by, _save);
        undrawColor = color.guiM;
    }

    void preview(in Level lev)
    {
        _title.text = lev.name;
        _by.value = lev.author;
        _save.value = format!"%d/%d"(lev.required, lev.initial);
    }
}

class ReplayNameplate : Element {
private:
    Label _title;
    LabelTwo _player;
    LabelTwo _pointsTo;

public:
    this(Geom g)
    in {
        assert (geom.ylg >= 60f);
    }
    body {
        super(g);
        _title = new Label(new Geom(0, 0, xlg, 20));
        _title.undrawBeforeDraw = true;
        _player = new LabelTwo(new Geom(0, 20, xlg, 20),
            Lang.browserInfoPlayer.transl);
        _pointsTo = new LabelTwo(new Geom(0, 40, xlg, 20),
            "\u27F6"); // Unicode: long arrow right
        addChildren(_title, _player, _pointsTo);
        undrawColor = color.guiM;
    }

    void preview(in Replay rep, in Level lev)
    {
        _title.text = lev.name;
        _player.value = rep.players.byValue.map!(p => p.name).join(", ");
        rep.levelFilename.match!(
            () {
                _pointsTo.hide();
            },
            (f) {
                _pointsTo.show();
                _pointsTo.value = f.rootless;
            }
        );
    }
}
