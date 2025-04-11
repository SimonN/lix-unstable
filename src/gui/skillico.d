module gui.skillico;

public import basics.netenums;

import graphic.internal;
import gui.cutbitel;
import gui.geometry;

class SkillIcon : CutbitElement {
public:
    this(Geom g, Style st = Style.garden)
    {
        super(g, Spritesheet.skillsInPanel.toCutbitFor(st));
    }

    Ac ac(in Ac _ac) pure nothrow @safe @nogc
    {
        xf = _ac.acToSkillIconXf;
        return _ac;
    }
}
