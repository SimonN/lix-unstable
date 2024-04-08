module gui.picker.highli;

import gui;
import gui.picker;

interface PickerNav {
    /*
     * The picker should call this once per calcSelf() with itself (the picker)
     * as argument.
     */
    void visit(Picker);
}

class NoKeyboardNav : PickerNav {
    void visit(Picker) {}
}

class UpDownKeyboardNav : PickerNav {
    void visit(Picker pi)
    {
        else if (keyMenuMoveByTotal() != 0) {
            _upDownToCanBeNull = super.moveHighlightBy(
                _upDownToCanBeNull ? _upDownToCanBeNull
                : _fileRecent, keyMenuMoveByTotal);
            highlightIfInCurrentDir(_upDownToCanBeNull); // may be null here
        }

    }

    static private int keyMenuMoveByTotal()
    {
        return opt.keyMenuUpBy1  .keyTappedAllowingRepeats * -1
            +  opt.keyMenuUpBy5  .keyTappedAllowingRepeats * -5
            +  opt.keyMenuDownBy1.keyTappedAllowingRepeats * 1
            +  opt.keyMenuDownBy5.keyTappedAllowingRepeats * 5;
    }
}
