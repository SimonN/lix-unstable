module basics.netenums;

public import net.ac;
public import net.plnr;
public import net.phyu;
public import net.style;

import basics.enum2str;

import std.uni;

int acToSkillIconXf(in Ac ac) pure nothrow @safe @nogc
{
    // We had xf = _ac before instead of xf = _ac - Ac.walker.
    // But the smallest skill in the panel is walker.
    // We can remove empty boxes from the image, saving VRAM & speed.
    return ac - Ac.walker
        - (ac > Ac.ascender) - (ac > Ac.shrugger) - (ac > Ac.shrugger2);
}

Ac stringFrom2006LevelFormatToAc(in string str) pure nothrow @safe @nogc
{
    switch (str) {
        case "WALKER": return Ac.walker;
        case "RUNNER": return Ac.runner;
        case "CLIMBER": return Ac.climber;
        case "FLOATER": return Ac.floater;
        case "EXPLODER": return Ac.imploder;
        case "EXPLODER2": return Ac.exploder;
        case "BLOCKER": return Ac.blocker;
        case "BUILDER": return Ac.builder;
        case "PLATFORMER": return Ac.platformer;
        case "BASHER": return Ac.basher;
        case "MINER": return Ac.miner;
        case "DIGGER": return Ac.digger;
        case "JUMPER": return Ac.jumper;
        case "BATTER": return Ac.batter;
        case "CUBER": return Ac.cuber;
        default: return Ac.nothing;
    }
}

string acToStringFor2006LevelFormat(in Ac ac) pure nothrow @safe @nogc
{
    final switch (ac) {
        case Ac.walker: return "WALKER";
        case Ac.runner: return "RUNNER";
        case Ac.climber: return "CLIMBER";
        case Ac.floater: return "FLOATER";
        case Ac.imploder: return "EXPLODER";
        case Ac.exploder: return "EXPLODER2";
        case Ac.blocker: return "BLOCKER";
        case Ac.builder: return "BUILDER";
        case Ac.platformer: return "PLATFORMER";
        case Ac.basher: return "BASHER";
        case Ac.miner: return "MINER";
        case Ac.digger: return "DIGGER";
        case Ac.jumper: return "JUMPER";
        case Ac.batter: return "BATTER";
        case Ac.cuber: return "CUBER";

        case Ac.nothing:
        case Ac.faller:
        case Ac.tumbler:
        case Ac.stunner:
        case Ac.lander:
        case Ac.splatter:
        case Ac.burner:
        case Ac.drowner:
        case Ac.exiter:
        case Ac.ascender:
        case Ac.shrugger:
        case Ac.shrugger2:
            assert (false, "Can't export name of unassignable skill.");
    }
}

auto acToNiceCase(in Ac ac)
{
    string s = ac.toString;
    if (s[$-1] == '2') {
        // Cut the "2" from, e.g., "Shrugger2".
        s = s[0 .. $-1];
    }
    return s.asCapitalized;
}

unittest {
    assert (acToString(Ac.faller) == "FALLER");
    assert (stringToAc("builDER") == Ac.builder);
    assert (stringToAc("expLoder") == Ac.imploder);
    assert (stringToAc("eXploDer2") == Ac.exploder);
    assert (acToString(Ac.imploder) == "EXPLODER");
    assert (acToString(Ac.exploder) == "EXPLODER2");
    assert (acToNiceCase(Ac.faller).equal("Faller"));
    assert (acToNiceCase(Ac.shrugger2).equal("Shrugger"));
    assert (acToNiceCase(Ac.imploder).equal("Imploder"));
}
