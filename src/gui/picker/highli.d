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

}

class UpDownKeyboardNav : PickerNav {


    static private int keyMenuMoveByTotal()
    {
        return opt.keyMenuUpBy1  .keyTappedAllowingRepeats * -1
            +  opt.keyMenuUpBy5  .keyTappedAllowingRepeats * -5
            +  opt.keyMenuDownBy1.keyTappedAllowingRepeats * 1
            +  opt.keyMenuDownBy5.keyTappedAllowingRepeats * 5;
    }
}
