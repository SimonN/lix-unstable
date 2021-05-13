module menu.namepl.forlevel;

import std.algorithm;
import std.format;
import std.range;

import graphic.color;
import file.language;
import level.level;
import menu.namepl.base;
import gui;

class LevelNameplate : Element, Nameplate {
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
        _by = new LabelTwo(new Geom(0, 20, xlg, 20),
            Lang.browserInfoAuthor.transl);
        _save = new LabelTwo(new Geom(0, 40, xlg, 20),
            Lang.browserInfoInitgoal.transl);
        addChildren(_title, _by, _save);
        undrawColor = color.guiM;
    }

    void preview(Level lev)
    {
        show();
        _title.text = lev.name;
        _by.value = lev.author;
        _save.value = format!"%d/%d"(lev.required, lev.initial);
    }

    void previewNone()
    {
        hide();
    }
}
