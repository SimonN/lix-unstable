module editor.editor;

/* I would like some MVC separation here. The model is class Level.
 * The Editor is Controller and View.
 */

import enumap;

import editor.calc;
import editor.dragger;
import editor.draw;
import editor.gui.browter;
import editor.gui.okcancel;
import editor.hover;
import editor.io;
import editor.gui.panel;
import file.filename;
import graphic.map;
import level.level;
import tile.occur;
import tile.gadtile;

class Editor {
package:
    Map      _map; // level background color, and gadgets
    Map      _mapTerrain; // transp, for rendering terrain, later blit to _map
    Level    _level;
    MutFilename _loadedFrom;

    bool _gotoMainMenu;
    EditorPanel _panel;
    MouseDragger _dragger;

    Hover[] _hover;
    Hover[] _selection;

    TerrainBrowser _terrainBrowser;
    OkCancelWindow _okCancelWindow;

public:
    this(Filename fn)
    {
        _loadedFrom = fn;
        this.implConstructor();
    }

    ~this() { this.implDestructor(); }

    bool gotoMainMenu() const { return _gotoMainMenu; }

    // Let's prevent data loss from crashes inside the editor.
    // When you catch a D Error (e.g., assertion failure) in the app's main
    // loop, tell the editor to dump the level.
    void emergencySave() const
    {
        import basics.globals;
        _level.saveToFile(new Filename(dirLevels.dirRootless
                                       ~ "editor-emergency-save.txt"));
    }

    void calc() { this.implEditorCalc(); }
    void draw() { this.implEditorDraw(); }
}
