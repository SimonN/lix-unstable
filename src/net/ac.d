module net.ac;

/*
 * Activity enum for the lixes.
 * This is in net/, not in lix/, because it has to travel over the network.
 *
 * If you must convert these to string or back, import basics.netenums.
 */

enum int skillInfinity  = -1;
enum int skillNumberMax = 999;

enum int builderBrickXl  = 12;
enum int platformLongXl  = 8; // first brick
enum int platformShortXl = 6; // all bricks laid down while kneeling
enum int brickYl         = 2;

enum PhyuOrder {
    peaceful, // Least priority -- cannot affect other lix. Phyud last.
    adder,    // Worker that adds terrain. Adders may add in fresh holes.
    remover,  // Worker that removes terrain.
    blocker,  // Affects lixes directly other than by flinging -- blocker.
    flinger,  // Affects lixes directly by flinging. Phyud first.
}


enum Ac : ubyte {
    nothing,
    faller,
    tumbler,
    stunner,
    lander,
    splatter,
    burner,
    drowner,
    exiter,
    walker,
    runner,

    climber,
    ascender,
    floater,
    imploder,
    exploder,
    blocker,
    builder,
    shrugger,
    platformer,
    shrugger2,
    basher,
    miner,
    digger,

    jumper,
    batter,
    cuber,
}

bool isPloder(in Ac ac) pure nothrow @safe @nogc
{
    return ac == Ac.imploder || ac == Ac.exploder;
}

bool isPermanentAbility(in Ac ac) pure nothrow @safe @nogc
{
    return ac == Ac.climber || ac == Ac.floater || ac == Ac.runner;
}

bool isLeaving(in Ac ac) pure nothrow @safe @nogc
{
    return ac == Ac.nothing
        || ac == Ac.splatter
        || ac == Ac.burner
        || ac == Ac.drowner
        || ac == Ac.exiter
        || ac == Ac.cuber;
}

bool appearsInPanel(in Ac ac) pure nothrow @safe @nogc
{
    return ac == Ac.walker
        || ac == Ac.runner
        || ac == Ac.climber
        || ac == Ac.floater
        || ac == Ac.imploder
        || ac == Ac.exploder
        || ac == Ac.blocker
        || ac == Ac.builder
        || ac == Ac.platformer
        || ac == Ac.basher
        || ac == Ac.miner
        || ac == Ac.digger
        || ac == Ac.jumper
        || ac == Ac.batter
        || ac == Ac.cuber;
}
