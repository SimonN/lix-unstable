module physics.nuking;

import optional;
import net.phyu;

struct Nuking {
    int overtimeAtStartInPhyus;
    int overtimeRemainingInPhyus;
    Optional!Phyu overtimeTriggeredAt;
    Optional!Phyu allAgreedToAbortAt;

    const pure nothrow @safe @nogc:
    bool overtimeTriggered() { return ! overtimeTriggeredAt.empty; }
    bool allAgreedToAbort() { return ! allAgreedToAbortAt.empty; }
    bool goalsAreOpen() { return ! nukeIsAssigningExploders; }
    bool nukeIsAssigningExploders()
    {
        return overtimeTriggered && overtimeRemainingInPhyus == 0
            || allAgreedToAbort;
    }
}
