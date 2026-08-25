.pragma library

// Process helpers shared by the services that keep a child running for the
// whole session.
//
// This lives in Services rather than Commons/Util.qml on purpose. Commons
// already imports qs.Services (Color and Style both do); making Services
// import qs.Commons back would close a module cycle that does not exist
// today. A plain .js file has no module to cycle with, and Services already
// uses the pattern -- Nm.qml imports NmParse.js the same way.

// Wraps a long-lived child so it dies with the shell.
//
// Quickshell kills a Process when its `running` goes false, but a SIGTERM to
// the shell itself never gets that far: the child is reparented to init and
// survives. For a one-shot read that is invisible. pshell has two children
// meant to outlive nothing but the session -- SystemTheme's `gsettings
// monitor` and Nm's `nmcli monitor` -- and those leak one stray process per
// run. Thirty-one abandoned `gsettings monitor` processes were found on the
// development machine, which is a fair measure of how long this went unseen.
//
// PR_SET_PDEATHSIG is the kernel's answer and setpriv exposes it without a
// helper binary of our own. The sh layer exists only so a system without
// util-linux gets a working monitor rather than a dead one; argv arrives as
// positional parameters instead of being interpolated into the script, so a
// value carrying a space or a quote cannot escape it.
function supervised(argv) {
    return ["sh", "-c", 'command -v setpriv >/dev/null 2>&1 && exec setpriv --pdeathsig TERM -- "$@"; exec "$@"', "sh"].concat(argv);
}
