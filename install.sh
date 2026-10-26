#!/bin/sh
#
# install.sh - install what pshell uses, then set it up.
#
# Two halves, in this order:
#
#   1. Packages. Quickshell and git are all pshell itself needs; everything
#      else is a feature's program, listed in wiki/getting-started.md. Each
#      one is installed from the repos when the repos have it and from the
#      AUR (through yay or paru) when they do not, so the same list works on
#      Arch and on CachyOS, where more of it is packaged.
#
#   2. Setup. The checkout, config.json, the `pshell` command on PATH, the
#      AI usage helper, and walker's elephant service.
#
# What it will not do: start the bar, edit your Hyprland config, or enable
# system services. A second bar next to a running one is two bars; your
# Hyprland config is yours; and switching on NetworkManager on a machine
# that runs iwd takes the network down. It prints those steps instead.
#
# Safe to run again. Anything already installed or already set up is left
# as it is, and config.json is never overwritten.

set -eu

usage() {
    cat <<'EOF'
usage: install.sh [options]

Installs the packages pshell uses, then sets it up.

  -y, --yes          do not ask before installing packages
  -n, --dry-run      print what would be done, change nothing
      --core         only install what pshell itself needs (quickshell, git)
      --no-aur       never use the AUR; report what is missing instead
      --skip-packages  only do the setup
      --skip-setup     only install packages
  -h, --help         show this

The checkout is the one this script sits in. Run from anywhere else (piped
from curl, say), it clones into $PSHELL_DIR, or ~/.config/quickshell/pshell.
EOF
}

yes=0
dry=0
core=0
aur=1
packages=1
setup=1

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes) yes=1 ;;
        -n|--dry-run) dry=1 ;;
        --core) core=1 ;;
        --no-aur) aur=0 ;;
        --skip-packages) packages=0 ;;
        --skip-setup) setup=0 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'install.sh: unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

say() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

# Runs a command, or in a dry run only shows it.
act() {
    if [ "$dry" = 1 ]; then
        printf '    would run: %s\n' "$*"
    else
        "$@"
    fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# sudo is for pacman alone, so running the whole script as root would put
# the checkout, config.json and the symlinks in root's home instead of yours.
[ "$(id -u)" != 0 ] || die "run this as yourself, not root; it asks for sudo when it needs it"

# ---------------------------------------------------------------- packages

# One line per thing to install: the packages that can provide it, best
# first, separated by |, then what it is for. The first of them already
# installed means there is nothing to do; otherwise the first the repos
# carry wins, and failing that the first one goes to the AUR. That is why
# walker is listed before walker-bin and cachy-update before arch-update:
# each is the packaged name where it is packaged.
CORE='
quickshell              pshell itself
git                     pshell itself
'

FEATURES='
matugen|matugen-bin     colours from the wallpaper
brightnessctl           screen and keyboard backlight
wl-clipboard            clipboard history
wtype                   clipboard history (pasting)
perl                    clipboard history
util-linux              clipboard history and nightlight (setpriv)
psmisc                  the privacy indicator (fuser)
hyprsunset              nightlight
cachy-update|arch-update  the update count
walker|walker-bin       the app launcher
elephant-all-bin        the app launcher (walker'"'"'s backend)
swayosd                 the volume and brightness popup
hypridle                locking on idle and before sleep
libvips|imagemagick     wallpaper thumbnails
pipewire                the volume tone (pw-play)
sound-theme-freedesktop the volume tone
glib2                   following the desktop'"'"'s light or dark setting
tailscale               the Tailscale widget
power-profiles-daemon   the power profile picker
networkmanager          the network widget and Wi-Fi tile
bluez                   the Bluetooth widget and tile
go                      building the AI usage helper
sqlite                  AI usage from opencode
'

aur_helper() {
    for h in yay paru; do
        if have "$h"; then
            printf '%s' "$h"
            return
        fi
    done
}

# pacman -T answers through provides as well as names, so tuned-ppd counts
# as power-profiles-daemon and elephant-all-bin as elephant.
installed() { pacman -T "$1" >/dev/null 2>&1; }
in_repos() { pacman -Si "$1" >/dev/null 2>&1; }

install_packages() {
    have pacman || die "pacman not found; this script is for Arch and Arch-based systems like CachyOS"

    list=$CORE
    [ "$core" = 1 ] || list="$list$FEATURES"

    repo=''
    from_aur=''
    missing=''

    say "Checking packages"
    # The here-document keeps the loop in this shell, so the lists it builds
    # survive it; a pipe would run it in a subshell and lose them.
    while read -r choices what; do
        [ -n "$choices" ] || continue

        # TLP and auto-cpufreq do the same job as power-profiles-daemon and
        # fight it if both run, so having either means you chose them.
        if [ "$choices" = power-profiles-daemon ]; then
            if installed tlp || installed auto-cpufreq; then
                note "skipping power-profiles-daemon: TLP or auto-cpufreq is installed"
                continue
            fi
        fi

        got=0
        for p in $(printf '%s' "$choices" | tr '|' ' '); do
            if installed "$p"; then
                got=1
                break
            fi
        done
        [ "$got" = 0 ] || continue

        pick=''
        for p in $(printf '%s' "$choices" | tr '|' ' '); do
            if in_repos "$p"; then
                pick=$p
                break
            fi
        done

        if [ -n "$pick" ]; then
            note "$pick ($what)"
            repo="$repo $pick"
        else
            first=${choices%%|*}
            if [ "$aur" = 1 ]; then
                note "$first, from the AUR ($what)"
                from_aur="$from_aur $first"
            else
                missing="$missing $first"
            fi
        fi
    done <<EOF
$list
EOF

    if [ -z "$repo$from_aur$missing" ]; then
        note "everything is already installed"
        return
    fi

    confirm=''
    [ "$yes" = 0 ] || confirm=--noconfirm

    if [ -n "$repo" ]; then
        say "Installing from the repos"
        # shellcheck disable=SC2086 # word splitting is the point
        act sudo pacman -S --needed $confirm $repo
    fi

    if [ -n "$from_aur" ]; then
        helper=$(aur_helper)
        if [ -n "$helper" ]; then
            say "Installing from the AUR with $helper"
            # shellcheck disable=SC2086
            act "$helper" -S --needed $confirm $from_aur
        else
            missing="$missing$from_aur"
        fi
    fi

    if [ -n "$missing" ]; then
        warn "not installed:$missing"
        warn "install yay or paru to get them from the AUR, or install them yourself; the features that use them hide until then"
    fi
}

# ---------------------------------------------------------------- setup

self=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")
here=$(dirname "$self")

find_checkout() {
    if [ -f "$here/shell.qml" ]; then
        checkout=$here
        return
    fi

    checkout=${PSHELL_DIR:-$HOME/.config/quickshell/pshell}
    if [ -f "$checkout/shell.qml" ]; then
        return
    fi
    if [ -e "$checkout" ]; then
        die "$checkout exists but is not a pshell checkout; move it or set PSHELL_DIR"
    fi

    have git || die "git is needed to fetch pshell; install it, or run without --skip-packages"
    say "Cloning pshell into $checkout"
    act mkdir -p "$(dirname "$checkout")"
    act git clone https://github.com/hdprajwal/pshell "$checkout"
}

# A symlink at $2 pointing at $1. One that already points there is fine; one
# pointing elsewhere is replaced, since it is a link we put there or a stale
# one; a real file is left alone, because it is not ours to delete.
link() {
    target=$1
    at=$2
    if [ -L "$at" ]; then
        [ "$(readlink -f "$at")" != "$(readlink -f "$target")" ] || return 0
        act ln -sfn "$target" "$at"
    elif [ -e "$at" ]; then
        warn "$at exists and is not a symlink; leaving it alone"
        return 0
    else
        act ln -s "$target" "$at"
    fi
    note "$at -> $target"
}

# Go 1.24 or newer, read from `go env GOVERSION` (go1.27.1, with any suffix).
go_new_enough() {
    v=$(go env GOVERSION 2>/dev/null) || return 1
    v=${v#go}
    major=${v%%.*}
    rest=${v#*.}
    minor=${rest%%[!0-9]*}
    [ -n "$major" ] && [ -n "$minor" ] || return 1
    [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 24 ]; }
}

do_setup() {
    find_checkout
    bin=$HOME/.local/bin
    conf=$HOME/.config/pshell

    say "Setting up pshell from $checkout"
    act mkdir -p "$conf" "$bin"

    if [ -e "$conf/config.json" ]; then
        note "keeping your $conf/config.json"
    else
        act cp "$checkout/config.example.json" "$conf/config.json"
        [ "$dry" = 1 ] || note "wrote $conf/config.json from config.example.json"
    fi

    link "$checkout/bin/pshell" "$bin/pshell"

    # The one part of pshell that needs compiling. Without it the AI usage
    # widget hides itself, so a missing or old Go is a note, not a failure.
    if have go && go_new_enough; then
        say "Building the AI usage helper"
        if [ "$dry" = 1 ]; then
            note "would run: go build -o $bin/pshell-agents ./cmd/pshell-agents (in $checkout)"
        elif (cd "$checkout" && go build -o "$bin/pshell-agents" ./cmd/pshell-agents); then
            note "built $bin/pshell-agents"
        else
            warn "could not build pshell-agents; the AI usage widget stays hidden"
        fi
    else
        note "skipping the AI usage helper: it needs Go 1.24 or newer"
    fi

    # elephant is a user service. `elephant service enable` writes the unit
    # but does not start it, and walker without it finds nothing.
    if have elephant && have systemctl; then
        if systemctl --user is-active --quiet elephant.service 2>/dev/null; then
            note "elephant is already running"
        else
            say "Starting elephant, walker's backend"
            act elephant service enable
            act systemctl --user enable --now elephant.service || warn "could not start elephant.service"
        fi
    fi

    next_steps
}

next_steps() {
    say "Next steps"

    case ":$PATH:" in
        *":$bin:"*) ;;
        *) note "add ~/.local/bin to your PATH, so the pshell command is found" ;;
    esac

    # Either way of starting it counts: qs pointed at a checkout, or the
    # pshell command's own `run`. A bare mention of pshell does not, since
    # hypridle.conf names it for the lock command.
    hypr=$HOME/.config/hypr
    if grep -rqsF --exclude-dir=.git -e "qs -p $checkout" -e "quickshell/pshell" -e "pshell run" "$hypr" 2>/dev/null; then
        note "your Hyprland config already starts pshell"
    else
        note "start pshell with Hyprland. In hyprland.conf:"
        note "    exec-once = qs -p $checkout"
        note "or in hyprland.lua (Hyprland 0.55 and later):"
        note "    hl.on(\"hyprland.start\", function() hl.exec_cmd(\"qs -p $checkout\") end)"
    fi

    # pshell is the notification server, and only one can own the name.
    for d in mako swaync dunst; do
        if have pgrep && pgrep -x "$d" >/dev/null 2>&1; then
            note "$d is running; stop it, pshell serves notifications itself"
        fi
    done
    if have systemctl && systemctl --user is-active --quiet dms.service 2>/dev/null; then
        note "DankMaterialShell is running; stop it first: systemctl --user disable --now dms.service"
    fi

    # Active counts as well as enabled: power-profiles-daemon, for one, is
    # started over D-Bus and is never enabled at all.
    for unit in NetworkManager bluetooth power-profiles-daemon tailscaled; do
        if have systemctl \
            && systemctl cat "$unit.service" >/dev/null 2>&1 \
            && ! systemctl is-enabled --quiet "$unit.service" 2>/dev/null \
            && ! systemctl is-active --quiet "$unit.service" 2>/dev/null; then
            note "$unit is installed but not enabled; enable it if you want it: sudo systemctl enable --now $unit"
        fi
    done

    note "then run: pshell run"
}

# ---------------------------------------------------------------- main

[ "$dry" = 0 ] || say "Dry run: nothing will be changed"
[ "$packages" = 0 ] || install_packages
[ "$setup" = 0 ] || do_setup
say "Done"
