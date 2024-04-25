module gui.picker.highli;

import opt = file.option.allopts;
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
private:
    // Last-highlit entry (a dir or a file) that we highlit with up/down keys.
    // _upDownToCanBeNull cannot be Optional because Optional doesn't behave
    // well with Rebindable!Filename == MutFilename: Both together corrupt RAM.
    MutFilename _upDownToCanBeNull = null;

    void visit(Picker pi)
    {
        immutable mov = keyMenuMoveByTotal();
        if (mov == 0) {
            return;
        }
        if (_upDownToCanBeNull is null) {
            pi.moveHighlightBy(
        }
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
