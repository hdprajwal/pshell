pragma Singleton

import Quickshell

// Only one popout is open at a time, anywhere. A singleton rather than state
// on the bar, because a bar exists per monitor and opening a panel on one
// screen should still close whatever is open on another.
Singleton {
    id: root

    property var current: null

    function open(popout) {
        if (current === popout)
            return;

        const previous = current;
        // Assign first: closing the old one calls back into release(), and
        // that must not clear the popout being opened right now.
        current = popout;

        if (previous && typeof previous.close === "function")
            previous.close();
    }

    function release(popout) {
        if (current === popout)
            current = null;
    }

    function closeAll() {
        const previous = current;
        current = null;
        if (previous && typeof previous.close === "function")
            previous.close();
    }
}
