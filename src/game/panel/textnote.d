module game.panel.textnote;

import basics.help;
import basics.alleg5;
import opt = file.option.allopts;
import graphic.color;
import gui;

import std.algorithm;

class TextNote : Element {
private:
    int firstSmallLine = -1;
    Label[] _labels;

public:
    this(Geom g)
    {
        super(g);
        foreach (line; opt.livestreamNoteText.value.splitter('|')) {
            addLine(line);
        }
        foreach (size_t i, Label l; _labels) {
            l.move(0, ygFor(i & 0xFFFF));
        }
    }

protected:
    override void drawSelf()
    {
        al_draw_filled_rectangle(xs, ys,
            xs + xls, ys + yls, color.screenBorder);
    }

private:
    void addLine(in string msg)
    {
        auto next = new Label(new Geom(0, 0, xlg, 20f, From.TOP), msg);
        next.color = color.guiTextDark;

        if (firstSmallLine == -1 && next.tooLong(msg)) {
            firstSmallLine = _labels.len;
        }
        if (firstSmallLine >= 0) {
            next.font = djvuS;
        }
        addChild(next);
        _labels ~= next;
    }

    float ygFor(in int i)
    {
        return ylg / 2f
            + ygFromTopOfTextFor(i)
            - ygFromTopOfTextFor(_labels.len) / 2f;
    }

    float ygFromTopOfTextFor(in int i)
    {
        enum spacingBetweenBig = 16f;
        enum spacingBetweenSizes = 20f;
        enum spacingBetweenSmall = 10f;

        if (firstSmallLine == -1) {
            return i * spacingBetweenBig;
        }

        const numLines = _labels.len;
        const numBig = firstSmallLine;
        const numSmall = numLines - numBig;

        float yFromTop = 0f;
        for (int before = 0; before < i; ++before) {
            yFromTop
                += before < numBig - 1 ? spacingBetweenBig
                : before == numBig - 1 ? spacingBetweenSizes
                : spacingBetweenSmall;
        }
        return yFromTop;
    }
}
