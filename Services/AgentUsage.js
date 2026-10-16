.pragma library

// When Services/AgentUsage.qml runs pshell-agents, and with which flags, kept
// away from Quickshell so `node --test` can reach it -- the same split
// Weather.js and Updates.js are on.
//
// There are three kinds of run and they cost very different amounts:
//
//   "full"   the timer's run. Rescans ~/.claude/projects and Codex's
//            rollouts, starts the Codex app-server, asks Fireworks for its
//            billing. This is what keeps the token counts honest.
//   "open"   the panel opening. The person wants the limits right now, not a
//            rescan of a month of session logs they last saw minutes ago, so
//            it is --limits-only: the collector reuses any scan younger than
//            its own window and only re-probes the limits.
//   "retry"  a collector said its probe failed for want of a network
//            (retryAdvised). Only those providers, only their limits.

// An opened panel within this long of the last finished run does not start
// another. Toggling the panel to glance at it should not cost a Fireworks
// round trip each time, and a minute-old limit is not a stale one.
var OPEN_THROTTLE_MS = 60 * 1000;

// The first retry comes quickly because the usual cause -- the bar starting
// before DHCP has handed out a route -- is over in seconds. It backs off from
// there so a machine that is genuinely offline is not probed every half
// minute for the rest of the afternoon.
var RETRY_FIRST_SEC = 30;
var RETRY_MAX_SEC = 300;

// The argument vector after `pshell-agents` for a run of `kind`. `targets`
// only matters for a retry; one with none degrades to every provider's
// limits, which is still cheaper than the full run it would otherwise wait for.
function updaterArgs(kind, targets) {
    if (kind === "open")
        return ["--limits-only"];
    if (kind === "retry")
        return ["--limits-only"].concat((targets || []).map(String).filter(id => id !== ""));
    return [];
}

// Whether opening the panel should run the updater. `lastFinishedMs` is when
// the previous run of any kind exited, or 0 when none has.
function openRefreshDue(lastFinishedMs, nowMs) {
    const last = Number(lastFinishedMs) || 0;
    if (last <= 0)
        return true;
    // A clock that went backwards -- suspend, an NTP step -- is not a reason
    // to refuse a refresh until it catches up.
    const age = Number(nowMs) - last;
    return age < 0 || age >= OPEN_THROTTLE_MS;
}

// The ids of every record asking to be retried, sorted so the same set always
// produces the same command line.
function retryTargets(records) {
    const ids = [];
    const list = records || [];
    for (var i = 0; i < list.length; i++) {
        const record = list[i];
        if (record && record.retryAdvised === true && record.id)
            ids.push(String(record.id));
    }
    ids.sort();
    return ids;
}

// Seconds to wait before retry number `attempt` (0 for the first). Never
// later than the regular timer: a retry scheduled after the next full run is
// one that run has already made pointless.
function retryDelaySec(attempt, intervalSec) {
    const n = Math.max(0, Math.floor(Number(attempt) || 0));
    // The exponent is capped so a long outage cannot grow it without bound.
    const delay = Math.min(RETRY_MAX_SEC, RETRY_FIRST_SEC * Math.pow(2, Math.min(n, 10)));
    const interval = Number(intervalSec);
    if (isFinite(interval) && interval > 0)
        return Math.min(delay, interval);
    return delay;
}
