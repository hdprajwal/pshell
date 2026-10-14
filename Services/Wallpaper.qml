pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Which wallpaper is current, and what the candidates are.
//
// A singleton rather than state on the background window: the window exists
// once per monitor under Variants, and "which wallpaper" is one fact per
// session, not one per screen -- the same reasoning that moved the idle
// inhibitor's state into Services/IdleInhibit.qml. Owning it here also gives
// it one IPC target, so a keybind can cycle wallpapers with no widget on the
// bar at all.
Singleton {
    id: root

    // The config is the source of truth; this service keeps no second copy.
    // Everything that changes the wallpaper goes through set() below, and
    // everything that displays it reads this.
    readonly property string current: Config.wallpaperPath

    // Absolute paths of the images in Config.wallpaperDir, sorted.
    property var entries: []

    // Image path -> a small cached copy of it, from
    // Services/wallpaper-thumbs.sh: 640x360 for the settings grid, 1280x720
    // for the carousel's cards. Nothing reads the originals for a preview
    // any more -- decoding a directory of 4K PNGs on Qt's one image thread
    // took the grid most of twenty seconds, every time the tab was opened.
    //
    // A path missing here has no thumbnail yet, or cannot have one (not an
    // image, or neither libvips nor ImageMagick installed). Entries survive
    // a rescan until the new run replaces them: a stale thumbnail for a
    // second is fine, a grid going blank on every rescan is not.
    property var thumbs: ({})
    property var previews: ({})

    function thumb(path) {
        return root.thumbs[path] || "";
    }

    function preview(path) {
        return root.previews[path] || "";
    }

    // One write, and that is the whole mechanism -- deliberately. Theme.qml
    // already watches wallpaperPath and re-runs matugen, which recolours the
    // bar and re-renders every template. Calling into Theme from here would
    // be a second path to the same effect, and two paths is how the palette
    // ends up disagreeing with the painted image.
    function set(path) {
        const p = Config.expandHome(String(path || ""));
        if (p === "") {
            console.warn("pshell: wallpaper set needs a path");
            return;
        }
        // Checked before it is written, because a broken value in
        // config.json outlives the typo that put it there: the background
        // falls back to a flat colour and matugen starts failing on every
        // refresh until someone finds the stale path by hand.
        root._candidate = p;
        checker.command = ["sh", "-c", 'test -f "$1"', "sh", p];
        checker.running = false;
        checker.running = true;
    }

    function next() {
        _step(1);
    }

    function previous() {
        _step(-1);
    }

    function _step(delta) {
        if (root.entries.length === 0)
            return;
        const at = root.entries.indexOf(root.current);
        // A current wallpaper set by hand from outside the directory is not
        // in entries; start the cycle at the first one rather than failing.
        if (at < 0) {
            set(root.entries[0]);
            return;
        }
        set(root.entries[(at + delta + root.entries.length) % root.entries.length]);
    }

    function random() {
        if (root.entries.length === 0)
            return;
        if (root.entries.length === 1) {
            set(root.entries[0]);
            return;
        }
        // Never the one already up: "random" from a keybind means "surprise
        // me", and the same picture again reads as the keybind not working.
        var pick;
        do {
            pick = root.entries[Math.floor(Math.random() * root.entries.length)];
        } while (pick === root.current);
        set(pick);
    }

    function rescan() {
        // The directory is an argument, not spliced into the script: a
        // wallpaper directory with a space or a quote in its name is a
        // path, not shell syntax.
        scanner.command = ["sh", "-c", 'dir="$1"; [ -d "$dir" ] || exit 0; find "$dir" -maxdepth 1 -type f \\( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.webp" \\) | sort', "sh", Config.wallpaperDir];
        scanner.running = false;
        scanner.running = true;
    }

    Component.onCompleted: rescan()

    Connections {
        target: Config

        function onWallpaperDirChanged() {
            root.rescan();
        }
    }

    property string _candidate: ""

    Process {
        id: checker

        onExited: code => {
            if (code === 0) {
                Config.set("wallpaper", root._candidate);
                return;
            }
            console.warn("pshell: no such wallpaper:", root._candidate);
        }
    }

    Process {
        id: scanner

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = String(text || "").split("\n");
                const found = [];
                for (var i = 0; i < lines.length; i++) {
                    const line = lines[i].trim();
                    if (line !== "")
                        found.push(line);
                }
                root.entries = found;
                root._thumbnail();
            }
        }
    }

    // ------------------------------------------------------------ thumbnails

    readonly property string _thumbScript: Quickshell.shellDir + "/Services/wallpaper-thumbs.sh"

    // Lines read but not yet published, per tier.
    property var _pendingThumbs: ({})
    property var _pendingPreviews: ({})
    property bool _stopping: false

    // One run per tier, the grid's first and the carousel's after it, never
    // both at once. Each already puts a worker on every core, so running
    // them together would not finish sooner -- it would only halve the speed
    // of the grid, which is the one somebody is usually looking at. A warm
    // cache makes each run a fraction of a second anyway.
    //
    // A rescan mid-run starts over with the new list. _stopping keeps the
    // killed grid run's exit from starting the carousel tier on the old one.
    function _thumbnail() {
        root._stopping = true;
        previewRun.running = false;
        gridRun.running = false;
        root._stopping = false;
        if (root.entries.length === 0)
            return;
        gridRun.command = ["bash", root._thumbScript, "640", "360"].concat(root.entries);
        gridRun.running = true;
    }

    function _read(line, pending) {
        const tab = line.indexOf("\t");
        if (tab <= 0)
            return;
        pending[line.slice(0, tab)] = line.slice(tab + 1);
        if (!publish.running)
            publish.start();
    }

    // Lines arrive one per image, and on a warm cache all forty-odd inside a
    // few milliseconds. Publishing each by reassigning the map would make
    // every grid delegate re-evaluate its binding once per line; this lets
    // them through in a few batches instead. start(), not restart(): a
    // steady trickle on a cold cache must still show up as it goes, not
    // wait for the last line.
    function _publish() {
        if (Object.keys(root._pendingThumbs).length > 0) {
            root.thumbs = Object.assign({}, root.thumbs, root._pendingThumbs);
            root._pendingThumbs = {};
        }
        if (Object.keys(root._pendingPreviews).length > 0) {
            root.previews = Object.assign({}, root.previews, root._pendingPreviews);
            root._pendingPreviews = {};
        }
    }

    Timer {
        id: publish

        interval: 100
        onTriggered: root._publish()
    }

    Process {
        id: gridRun

        stdout: SplitParser {
            onRead: line => root._read(line, root._pendingThumbs)
        }
        // The script's own complaints only -- it silences the tools'
        // per-file noise -- so anything here is worth a line in the log.
        stderr: SplitParser {
            onRead: line => console.warn("pshell:", line)
        }
        onExited: code => {
            root._publish();
            // A non-zero exit is "no tool to make thumbnails with", which
            // the carousel tier would only say again.
            if (code !== 0 || root._stopping || gridRun.running)
                return;
            previewRun.command = ["bash", root._thumbScript, "1280", "720"].concat(root.entries);
            previewRun.running = true;
        }
    }

    Process {
        id: previewRun

        stdout: SplitParser {
            onRead: line => root._read(line, root._pendingPreviews)
        }
        onExited: root._publish()
    }

    IpcHandler {
        target: "pshell.wallpaper"

        function set(path: string): void {
            root.set(path);
        }

        function next(): void {
            root.next();
        }

        function previous(): void {
            root.previous();
        }

        function random(): void {
            root.random();
        }

        function current(): string {
            return root.current;
        }

        function list(): string {
            return root.entries.join("\n");
        }

        function rescan(): void {
            root.rescan();
        }

        // The fullscreen picker's door, on this target rather than its own:
        // one wallpaper noun on the command line -- `pshell wallpaper
        // carousel` beside `pshell wallpaper next` -- and mentioning the
        // singleton here is also what brings it to life, so shell.qml needs
        // no keep-alive line for it. The carousel state itself stays in
        // Services/WallpaperCarousel.qml; this handler only forwards.
        //
        // Open and close exist besides the toggle for the reason IdleInhibit
        // gives for on/off: a script that wants the overlay up should ask
        // for that, not for "the other thing".
        function carousel(): string {
            WallpaperCarousel.toggle();
            return WallpaperCarousel.visible ? "opened" : "closed";
        }

        function carouselOpen(): string {
            WallpaperCarousel.open();
            return "opened";
        }

        function carouselClose(): string {
            WallpaperCarousel.close();
            return "closed";
        }
    }
}
