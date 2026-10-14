#!/bin/bash
#
# The clipboard history's hands: everything Services/Clipboard.qml needs done
# outside the QML engine, as one script with three verbs.
#
#   clipboard.sh capture [text|image/<type>]
#       Print the clipboard as one JSON line on stdout, or nothing. With a
#       type, wl-paste --watch is calling and the copy is on stdin; with
#       none, read the current selection directly (the snapshot at start).
#
#   clipboard.sh reap
#       Kill wl-paste watchers this shell has no further use for, before it
#       starts its own. See reap() for which ones, and which ones never.
#
#   clipboard.sh paste|copy [--type <mime> --file <path>]
#       Put an entry back on the clipboard -- text from stdin, or a file --
#       and for paste, send Shift+Insert to whatever has focus.
#
# The shell owns every process this starts, and nothing here outlives a
# copy: no daemon, no socket, no cliphist. capture is adapted from Omarchy's
# shell/plugins/clipboard/capture.sh and paste from its
# omarchy-clipboard-paste-text and -file (MIT, see NOTICE.md).

set -o pipefail

image_dir=${PSHELL_CLIPBOARD_IMAGES:-${XDG_STATE_HOME:-$HOME/.local/state}/pshell/clipboard-images}

# -------------------------------------------------------------------- capture

tmp=
trap 'rm -f -- "$tmp"' EXIT

# The clipboard owner streams the copy and can stall without ever closing its
# end, so every read is bounded. A copy cut off at the deadline is dropped,
# not kept half-read.
read_copy() {
    timeout 2s "$@" >"$tmp" 2>/dev/null && [[ -s $tmp ]]
}

# Images are stored by their sha256, so the same picture copied twice is one
# file and one history entry -- the path is the dedupe key.
emit_image() {
    local mime=$1 ext hash file
    shift

    ext=${mime#image/}
    [[ $ext == jpeg ]] && ext=jpg
    # The extension lands in a file name; a mime type is whatever the
    # clipboard owner said it was.
    [[ $ext =~ ^[A-Za-z0-9.+-]+$ ]] || ext=bin

    mkdir -p -- "$image_dir" || return 0
    tmp=$(mktemp --tmpdir="$image_dir" .capture.XXXXXX) || return 0
    read_copy "$@" || return 0

    hash=$(sha256sum <"$tmp") || return 0
    file=$image_dir/${hash%% *}.$ext
    if [[ -e $file ]]; then
        rm -f -- "$tmp"
    else
        mv -- "$tmp" "$file" || return 0
    fi
    tmp=

    MIME=$mime FILE=$file perl -MJSON::PP -e '
        print JSON::PP->new->canonical->encode({ type => "image", mime => $ENV{MIME}, path => $ENV{FILE} }), "\n";
    '
}

# Text is read as bytes and decoded here, because the clipboard does not
# promise UTF-8: a Windows app under Wine, and some Java ones, offer UTF-16.
emit_text() {
    tmp=$(mktemp) || return 0
    read_copy "$@" || return 0

    perl -MEncode=decode,FB_CROAK,LEAVE_SRC -MJSON::PP -0777 -e '
        my $raw = <STDIN>;
        exit unless length $raw;

        my $encoding;
        my $guessed = 0;
        if ($raw =~ /^(?:\xFF\xFE|\xFE\xFF)/) {
            $encoding = "UTF-16";
        } elsif (length($raw) % 2 == 0 && index($raw, "\0") >= 0) {
            my $units = length($raw) / 2;
            my $nuls = $raw =~ tr/\0/\0/;

            # Neither byte lane can reach the threshold below when the whole
            # payload has fewer NULs than that, so skip two full passes.
            if ($nuls * 4 >= $units * 3) {
                my $even = $raw;
                $even =~ s/(.)./$1/sg;
                my $even_nuls = $even =~ tr/\0/\0/;
                undef $even;

                my $odd = $raw;
                $odd =~ s/.(.)/$1/sg;
                my $odd_nuls = $odd =~ tr/\0/\0/;

                # BOM-less UTF-16 cannot be told from NUL-separated bytes for
                # certain. Decode only when three quarters of the code units
                # are padded in one lane and under a quarter in the other.
                if ($odd_nuls * 4 >= $units * 3 && $even_nuls * 4 < $units) {
                    $encoding = "UTF-16LE";
                    $guessed = 1;
                } elsif ($even_nuls * 4 >= $units * 3 && $odd_nuls * 4 < $units) {
                    $encoding = "UTF-16BE";
                    $guessed = 1;
                }
            }
        }

        my $text = $encoding ? eval { decode($encoding, $raw, FB_CROAK | LEAVE_SRC) } : undef;
        # A guess that decodes to control characters was a wrong guess.
        $text = undef if $guessed && defined($text) && $text =~ /[\x00-\x08\x0E-\x1A\x1C-\x1F]/;
        $text = decode("UTF-8", $raw) unless defined $text;
        print JSON::PP->new->canonical->encode({ type => "text", text => $text }), "\n";
    ' <"$tmp"
}

capture() {
    local types mime
    types=$(timeout 2s wl-paste --list-types 2>/dev/null || true)

    # Password managers say so: KeePassXC and friends offer this mime beside
    # the secret, and wl-paste --watch sets CLIPBOARD_STATE=sensitive for a
    # source that marks itself. Neither belongs in a file on disk.
    if [[ ${CLIPBOARD_STATE:-} == sensitive ]] || grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
        return 0
    fi

    case ${1:-} in
    text)
        emit_text cat
        return
        ;;
    image/*)
        emit_image "$1" cat
        return
        ;;
    esac

    for mime in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do
        if grep -qx "$mime" <<<"$types"; then
            emit_image "$mime" wl-paste --type "$mime"
            return
        fi
    done

    if grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING' <<<"$types" || grep -qx 'STRING' <<<"$types"; then
        emit_text wl-paste --type text --no-newline
    fi
}

# ----------------------------------------------------------------------- reap

# Which watchers go:
#
#   - ones whose parent is the process running this script. The shell starts
#     reap before its own watchers, so any it finds under itself are from an
#     earlier generation of the same process -- a config reload that left
#     its children running.
#   - ones whose parent is not a Quickshell at all. Every watcher is started
#     under `setpriv --pdeathsig TERM`, so this should be nobody; it is the
#     net for a watcher that survived anyway and was reparented to init.
#
# Which never do: a watcher whose parent is some *other* running Quickshell.
# That is a second pshell -- on a nested compositor, or another checkout --
# and its history is its own business. Omarchy's pkill takes every match,
# which is fine with one shell per machine and wrong with two.
reap() {
    local shell=$PPID pid argv parent exe

    for pid in $(pgrep -x wl-paste); do
        argv=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null) || continue
        case $argv in
        *" --watch "*"/clipboard.sh capture"*) ;;
        *) continue ;;
        esac

        parent=$(awk '{ print $4 }' "/proc/$pid/stat" 2>/dev/null) || continue
        exe=$(readlink "/proc/$parent/exe" 2>/dev/null || true)

        if [[ $parent == "$shell" ]]; then
            kill "$pid" 2>/dev/null
            continue
        fi
        case ${exe##*/} in
        quickshell | qs) ;;
        *) kill "$pid" 2>/dev/null ;;
        esac
    done
    return 0
}

# ---------------------------------------------------------------------- paste

paste() {
    local verb=$1 type= file=
    shift

    while (($# > 0)); do
        case $1 in
        --type)
            type=${2:-}
            shift 2
            ;;
        --file)
            file=${2:-}
            shift 2
            ;;
        *)
            echo "clipboard.sh: unknown option $1" >&2
            return 1
            ;;
        esac
    done

    local -a mime=()
    if [[ -n $file ]]; then
        [[ -r $file ]] || return 1
        mime=(--type "${type:-application/octet-stream}")
    else
        # Text arrives on stdin and is needed twice below, so it is spooled.
        tmp=$(mktemp) || return 1
        cat >"$tmp" || return 1
        file=$tmp
    fi

    # wl-copy forks to serve the selection and that child keeps running, so
    # it must not hold the shell's pipes open behind it.
    wl-copy "${mime[@]}" <"$file" >/dev/null 2>&1 || return 1

    [[ $verb == copy ]] && return 0

    # Shift+Insert is the one paste chord every app takes, Ctrl+V being
    # Ctrl+Shift+V in a terminal -- but kitty, alacritty and ghostty bind it
    # to the *primary* selection, and would paste whatever was last
    # highlighted instead. So a paste sets both. Copy-only leaves the
    # primary selection alone, since nothing is about to read it.
    wl-copy --primary "${mime[@]}" <"$file" >/dev/null 2>&1 || true

    # Long enough for the panel to unmap and the compositor to hand keyboard
    # focus back to the window the paste is meant for.
    sleep 0.15
    wtype -M shift -k Insert -m shift 2>/dev/null || true
}

case ${1:-} in
capture)
    shift
    capture "$@"
    ;;
reap)
    reap
    ;;
paste | copy)
    paste "$@"
    ;;
*)
    echo "usage: clipboard.sh capture [text|image/<type>] | reap | paste|copy [--type <mime> --file <path>]" >&2
    exit 2
    ;;
esac
