#!/bin/sh
#
# Lists the QML widgets under ~/.config/pshell/widgets for
# Services/WidgetRegistry.qml, and stages them for loading.
#
#   widgets.sh [<qtquick-version>]
#
# For each <widget>/manifest.json, prints
#
#   ===PSHELL===
#   <the widget's directory>
#   <the directory to load it from>
#   <manifest.json, verbatim>
#
# With no version the widget loads from where it lives. With one, it loads
# from a copy under ${XDG_CACHE_HOME:-~/.cache}/pshell/widgets, in which every
# bare `import QtQuick` reads `import QtQuick <version>`. That is what keeps a
# widget written for Omarchy working on Qt 6.12, whose QtQuick exports a
# `Color` singleton that shadows qs.Commons' palette in an unversioned import.
# Omarchy's shell does the same rewrite as it loads plugin QML. The widget's
# own files are someone else's and are only ever read.
#
# If the copy cannot be made, the widget loads from where it lives: it may
# lose its colours, but it is still there.

dir="$HOME/.config/pshell/widgets"
[ -d "$dir" ] || exit 0

pin="${1:-}"
stage="${XDG_CACHE_HOME:-$HOME/.cache}/pshell/widgets"

case "$pin" in
"") ;;
*[!0-9.]* | .* | *.)
    echo "widgets.sh: not a version: $pin" >&2
    exit 2
    ;;
*)
    # Rebuilt each time, so a widget removed or edited since the last start
    # leaves nothing stale behind.
    rm -rf "$stage"
    mkdir -p "$stage" || pin=""
    ;;
esac

for f in "$dir"/*/manifest.json; do
    [ -f "$f" ] || continue
    src=$(dirname "$f")
    load="$src"

    if [ -n "$pin" ]; then
        copy="$stage/$(basename "$src")"
        # -L, so a widget symlinked in from a checkout, or one with a QML
        # file symlinked into it, is copied as files; sed -i below then
        # rewrites the copy and cannot reach through a link to the original.
        if cp -RL "$src/." "$copy" 2>/dev/null &&
            find "$copy" -name '*.qml' -type f -exec sed -i -E \
                "s/^([[:space:]]*import[[:space:]]+QtQuick)[[:space:]]*;?[[:space:]]*\$/\\1 $pin/" {} +; then
            rm -rf "$copy/.git"
            load="$copy"
        else
            echo "widgets.sh: could not stage $src, loading it unpinned" >&2
        fi
    fi

    echo "===PSHELL==="
    echo "$src"
    echo "$load"
    cat "$f"
done
