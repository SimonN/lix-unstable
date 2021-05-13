module menu.namepl.base;

/*
 * A Nameplate is the structure of text labels below a Preview.
 * Usually, it describes a level, sometimes, it describes a replay. E.g.:
 *
 *      Any Way You Want
 *      By: Insane Steve
 *      Save: 1/10
 *
 * There should be some other class that combines a Nameplate with a Preview.
 *
 * There should be some other class that prints records. Or maybe a variant
 * of Nameplate?
 */

interface Nameplate {
    void previewNone();
}
