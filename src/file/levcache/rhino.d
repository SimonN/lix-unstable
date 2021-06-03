module file.levcache.rhino;

/*
 * Rhino: A node in the level database. Can be a leaf (level) or can point
 * to more nodes.
 *
 * For a level:
 *      weight = 1
 *      numCompleted = 0 or 1. It's 1 if the level solved, 0 otherwise
 *
 * For a directory:
 *      weight = sum of weights of the directory's contents
 *      numCompleted = sum of numCompleted of its contents
 */

import file.filename;
import file.levcache.db;

interface Rhino {
    const pure nothrow @safe @nogc {
        Filename filename();
        int weight();
        int numCompleted();
    }
    void recacheOnlyThis();
    void recacheRecursively();
}
