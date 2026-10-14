#!/bin/bash
#
# Small copies of the wallpapers, for Services/Wallpaper.qml to show in the
# settings grid and the carousel instead of the originals.
#
#   wallpaper-thumbs.sh <width> <height> <path>...
#       For each image, print
#
#           <the image's path>\t<its thumbnail's path>
#
#       one line as soon as that thumbnail is ready, in whatever order they
#       finish. An image that cannot be thumbnailed prints nothing.
#
# Why this exists: the originals are 4K PNGs of 10-20 MB each, and Qt decodes
# asynchronous images one at a time on a single reader thread. A directory of
# forty-eight took about 17 s to fill the grid, and the settings window throws the
# page away on every tab switch, so every visit paid it again. Here the
# decodes run on every core, once, and what the shell reads afterwards is a
# JPEG of a few kilobytes.
#
# Thumbnails live in ${XDG_CACHE_HOME:-~/.cache}/pshell/wallpaper-thumbs,
# named for the image's path, its mtime and size, and the size asked for. An
# image edited or replaced in place gets a new name, so a stale thumbnail is
# never shown for it; the old one ages out with the rest (see prune below).
#
# vipsthumbnail (libvips) if it is there, ImageMagick if not. With neither,
# this says so on stderr and prints nothing, and the shell shows empty plates
# rather than falling back to decoding the originals itself.
#
# Runs and exits: no daemon, no watcher. The shell runs it again after every
# directory scan, and everything already made is a stat and a touch.

set -o pipefail

cache="${XDG_CACHE_HOME:-$HOME/.cache}/pshell/wallpaper-thumbs"

# ------------------------------------------------------------------------ one

# One image, called by xargs below with the path as its own argument -- never
# spliced into a command line, so a name with a space or a quote in it is a
# name and not shell syntax.
one() {
    local w=$1 h=$2 src=$3 stamp key out tmp
    stamp=$(stat -c '%Y:%s' -- "$src" 2>/dev/null) || return 0
    key=$(printf '%s\n%s\n%sx%s' "$src" "$stamp" "$w" "$h" | md5sum) || return 0
    key=${key%% *}
    out="$cache/$key.jpg"

    if [[ -s $out ]]; then
        # Touched so the prune below sees it as in use; a thumbnail's mtime
        # is when it was last wanted, not when it was made.
        touch -c -- "$out" 2>/dev/null
        printf '%s\t%s\n' "$src" "$out"
        return 0
    fi

    # Written under a temporary name and moved into place, because the shell
    # may be reading the cache while this writes: a rename is atomic, and a
    # half-written JPEG would decode as a grey band at the bottom. The name
    # starts with a dot and ends in .jpg -- both tools pick the format from
    # the extension.
    tmp="$cache/.$key.$$.jpg"
    if command -v vipsthumbnail >/dev/null; then
        # VIPS_WARNING and the stderr drop are for a harmless warning about
        # openslide that some libvips builds print on every single call.
        VIPS_WARNING=0 vipsthumbnail "$src" --size "${w}x${h}" --smartcrop centre \
            -o "$tmp[Q=85,strip]" 2>/dev/null
    else
        # [0] is the first frame: an animated WebP is a wallpaper, not forty.
        # ^ fills the box and -extent crops the overflow from the centre, the
        # same cut PreserveAspectCrop makes in the shell.
        magick "$src[0]" -auto-orient -thumbnail "${w}x${h}^" -gravity center \
            -extent "${w}x${h}" -quality 85 -strip "$tmp" 2>/dev/null
    fi
    if [[ $? -eq 0 && -s $tmp ]] && mv -f -- "$tmp" "$out"; then
        # One short printf per line: well under PIPE_BUF, so lines from
        # parallel workers arrive whole, never spliced into each other.
        printf '%s\t%s\n' "$src" "$out"
    else
        rm -f -- "$tmp"
    fi
    return 0
}

if [[ $1 == one ]]; then
    one "$2" "$3" "$4"
    exit 0
fi

# ----------------------------------------------------------------------- main

w=$1 h=$2
if [[ ! $w =~ ^[1-9][0-9]*$ || ! $h =~ ^[1-9][0-9]*$ ]]; then
    echo "usage: wallpaper-thumbs.sh <width> <height> <path>..." >&2
    exit 2
fi
shift 2

if ! command -v vipsthumbnail >/dev/null && ! command -v magick >/dev/null; then
    echo "wallpaper-thumbs.sh: neither vipsthumbnail nor magick is installed; no thumbnails" >&2
    exit 1
fi

mkdir -p -- "$cache" || exit 1

# A worker per core, in the order given, so the first images in the grid are
# the first to be started. Under nice because none of this is urgent enough
# to make the rest of the desktop stutter for it. xargs -0 with the paths
# NUL-separated, so not even a newline in a file name splits one in two.
if (($# > 0)); then
    printf '%s\0' "$@" | nice -n 10 xargs -0 -n 1 -P "$(nproc)" "$BASH" "$0" one "$w" "$h"
fi

# Pruned last, so it never races the work above. Anything unused for sixty
# days goes -- without this the cache would keep a set of thumbnails for
# every directory ever pointed at and every version of every edited image.
# Temporary files a killed run left behind go after ten minutes, which no
# single thumbnail takes.
find "$cache" -maxdepth 1 -type f -name '*.jpg' -mtime +60 -delete 2>/dev/null
find "$cache" -maxdepth 1 -type f -name '.*.jpg' -mmin +10 -delete 2>/dev/null
exit 0
