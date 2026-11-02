.pragma library

// The idle inhibitor's clock arithmetic: when "until 18:30" ends, and how to
// say how long is left. Kept out of Services/IdleInhibit.qml so `node --test`
// can load it, as Nightlight.js is -- a time already past today has to mean
// tomorrow, and that is the kind of rule that is wrong by a day unnoticed.

// When a 24-hour "HH:MM" next comes round after `now`, in ms since the epoch,
// or -1 if the text is not one. The current minute counts as passed: asking
// at 14:00 for "until 14:00" means tomorrow, not an inhibitor that is off
// before it starts.
function endOfClock(text, now) {
    var match = /^\s*(\d{1,2}):(\d{2})\s*$/.exec(text === undefined || text === null ? "" : String(text));
    if (!match)
        return -1;
    var hours = Number(match[1]);
    var minutes = Number(match[2]);
    if (hours > 23 || minutes > 59)
        return -1;

    var end = new Date(now);
    end.setHours(hours, minutes, 0, 0);
    if (end.getTime() <= now)
        end.setDate(end.getDate() + 1);
    return end.getTime();
}

// "1h 12m", "45m", "2h". Rounded up, so a countdown never reads 0m while it
// is still running.
function formatLeft(ms) {
    var total = ms > 0 ? Math.ceil(ms / 60000) : 0;
    var hours = Math.floor(total / 60);
    var minutes = total % 60;
    if (hours === 0)
        return minutes + "m";
    return minutes === 0 ? hours + "h" : hours + "h " + minutes + "m";
}
