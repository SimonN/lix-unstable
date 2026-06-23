module physics.effect;

/*
 * The interface for the concrete effect manager of the game.
 * Lixxies and other physics don't need the full EffectManager or its drawing
 * functions or resetting functions. Lixxies merely need to queue their
 * effects to be drawn: They need a sink and don't care what happens then.
 */

import std.typecons;

public import basics.rect;
public import hardware.sound;
public import net.name;
public import net.ac;
public import net.phyu;

interface EffectSink {
public:
    void addSoundGeneral(in Phyu, in Sound sound);
    void addSound(in Phyu, in Name pa, in Sound sound);

    void addAssignment(in Phyu, in Name, in Point foot, in Ac, in Sound);

    void addShovel(in Phyu, in Name, in Point foot, in int dir);
    void addPickaxe(in Phyu, in Name, in Point foot, in int dir);
    void addDigHammer(in Phyu, in Name, in Point foot, in int dir);

    void addImplosion(in Phyu, in Name, in Point foot);
    void addExplosion(in Phyu, in Name, in Point foot);

    void announceOvertime(in Phyu, in int overtimeInPhyus);
}

alias NullEffectSink = BlackHole!EffectSink;
