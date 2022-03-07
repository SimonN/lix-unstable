module net.server.meta;

/*
 * Metaprogramming helpers to auto-implement classes that derive from
 * Outbox/Inbox and merely forward the calls to other Outboxes/Inboxes.
 */

import std.algorithm;
import std.array;
import net.server.outbox;

/*
 * Input: (void(in A a, in B b, C c))
 * Output: in A a, in B b, C c
 */
template ParamTypesAndNames(T, string func)
{
    enum string ParamTypesAndNames
        = typeof(__traits(getOverloads, T, func))
        .stringof[6 .. $-2];
    /*
     * Here, I assumed that all methods have return type void.
     * I cut off "(void(" and the final "))".
     * I thus leave: "in PlNr receiv, Arg1 arg1, Arg2 arg2"
     */
}

/*
 * Input: (void(in A a, in B b, C c))
 * Output: a, b, c
 */
template ParamNamesOnly(T, string func)
{
    enum string ParamNamesOnly
        = ParamTypesAndNames!(T, func)
        .splitter(", ")
        .map!toLastWord
        .join(", ");
}

private static string toLastWord(string words)
{
    while (words.findSkip(" ")) {}
    return words;
}
