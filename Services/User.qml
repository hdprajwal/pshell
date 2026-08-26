pragma Singleton

import Quickshell
import Quickshell.Io

// Who is logged in, for anything that has to say so.
//
// Read once at startup rather than polled: a username does not change under
// a running session, and neither does the file someone put at ~/.face.
//
// The avatar is resolved here rather than in the view because "which of
// these three paths exists" is a question about the machine, not about
// layout, and every consumer would otherwise re-answer it. AccountsService
// comes first because that is what GNOME's own settings writes when you
// pick a picture; ~/.face is the older convention that everything else
// still honours.
Singleton {
    id: root

    property string name: ""
    property string fullName: ""
    property string avatar: ""

    // What to print above a password field: the human's name if the system
    // knows one, otherwise the login. Never empty on a machine with a user.
    readonly property string displayName: fullName !== "" ? fullName : name

    readonly property bool hasAvatar: avatar !== ""

    // Same tab-separated shape as the About page's probe, for the same
    // reason: `emit` drops empty values, so a machine with no GECOS field
    // and no avatar file reports neither rather than reporting "unknown".
    //
    // `\\t` and `\\n` rather than `\t` and `\n`: QML resolves its own
    // escapes first, and printf has to receive the two characters.
    readonly property string probe: 'emit() { [ -n "$2" ] && printf \'%s\\t%s\\n\' "$1" "$2"; }
name="${USER:-$(id -un 2>/dev/null)}"
emit name "$name"
emit fullName "$(getent passwd "$name" 2>/dev/null | cut -d: -f5 | cut -d, -f1)"
for face in "/var/lib/AccountsService/icons/$name" "$HOME/.face" "$HOME/.face.icon"; do
  [ -r "$face" ] && { emit avatar "$face"; break; }
done'

    function apply(text) {
        const lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            const tab = lines[i].indexOf("\t");
            if (tab < 0)
                continue;
            const key = lines[i].slice(0, tab);
            const value = lines[i].slice(tab + 1).trim();
            if (key === "name")
                root.name = value;
            else if (key === "fullName")
                root.fullName = value;
            else if (key === "avatar")
                root.avatar = value;
        }
    }

    Process {
        running: true
        command: ["sh", "-c", root.probe]
        stdout: StdioCollector {
            onStreamFinished: root.apply(text)
        }
    }
}
