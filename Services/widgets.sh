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
# If a widget cannot be copied, it loads from where it lives: it may lose
# its colours, but it is still there. A file that cannot be read is skipped
# with a warning, and the rest of the widget is copied. Every warning goes to
# stderr, which WidgetRegistry logs.

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
    # leaves nothing stale behind. It is built beside the stage and swapped
    # in at the end, because another pshell (a test instance, a second
    # checkout) shares the stage, and a widget already running from it may
    # still load an asset or a panel from its copy.
    new="$stage.new.$$"
    old="$stage.old.$$"
    # Leftovers from a scan that was killed half way.
    for d in "$stage".new.* "$stage".old.*; do
        [ -d "$d" ] || continue
        kill -0 "${d##*.}" 2>/dev/null || rm -rf "$d"
    done
    rm -rf "$new"
    mkdir -p "$new" || pin=""
    ;;
esac

# Run in each copy for its symlinks, as: sh -c "$links" sh <widget> <copy> <link>...
#
# Links are copied as links, so one pointing at `..`, $HOME or / costs
# nothing, and one that dangles costs nothing either. A QML or JS file, or a
# qmldir, that is a link to a file is replaced by a copy of that file, so it
# is pinned like the rest and sed cannot reach through it to the original.
# Any other link that leads out of the widget is re-pointed at its absolute
# target, since a relative one would now resolve from the cache instead.
links='
src=$(realpath -e "$1") || exit 0
copy=$2
shift 2
for l in "$@"; do
    rel=${l#"$copy"/}
    target=$(realpath -e "$src/$rel" 2>/dev/null) || continue
    case "$rel" in
    *.qml | *.js | qmldir | */qmldir)
        if [ -f "$target" ]; then
            rm -f "$l" && cp "$target" "$l" ||
                echo "widgets.sh: could not copy $src/$rel" >&2
            continue
        fi
        ;;
    esac
    case "$target" in
    "$src" | "$src"/*) ;;
    *) ln -sfn "$target" "$l" ;;
    esac
done
'

for f in "$dir"/*/manifest.json; do
    [ -f "$f" ] || continue
    src=$(dirname "$f")

    if [ -n "$pin" ]; then
        copy="$new/$(basename "$src")"
        # tar, not cp, to leave .git and node_modules behind, and to keep
        # going past a file it cannot read. Neither tar follows a link.
        if mkdir "$copy" && {
            tar -C "$src/" --exclude=.git --exclude=node_modules -cf - . |
                tar -C "$copy" -xf -
            [ -f "$copy/manifest.json" ]
        }; then
            chmod -R u+w "$copy"
            find "$copy" -type l -exec sh -c "$links" sh "$src" "$copy" {} +
            # A bare `import QtQuick`, maybe with a `;`, a trailing comment
            # or a CRLF ending, gains the version. Anything with a version,
            # an alias or a submodule already is what it says.
            bare='^([[:space:]]*import[[:space:]]+QtQuick)[[:space:]]*;?[[:space:]]*'
            if ! find "$copy" -name '*.qml' -type f -exec sed -i -E \
                -e "s#$bare\r?\$#\\1 $pin#" \
                -e "s#$bare((//|/\\*).*)\$#\\1 $pin \\2#" {} +; then
                rm -rf "$copy"
            fi
        else
            rm -rf "$copy"
        fi
        [ -d "$copy" ] || echo "widgets.sh: could not stage $src, loading it unpinned" >&2
    fi
done

if [ -n "$pin" ]; then
    rm -rf "$old"
    if { [ ! -e "$stage" ] || mv "$stage" "$old"; } && mv "$new" "$stage"; then
        rm -rf "$old"
    else
        echo "widgets.sh: could not replace $stage, loading every widget unpinned" >&2
        rm -rf "$new"
        pin=""
    fi
fi

for f in "$dir"/*/manifest.json; do
    [ -f "$f" ] || continue
    src=$(dirname "$f")
    load="$src"
    if [ -n "$pin" ] && [ -d "$stage/$(basename "$src")" ]; then
        load="$stage/$(basename "$src")"
    fi

    echo "===PSHELL==="
    echo "$src"
    echo "$load"
    cat "$f"
done
