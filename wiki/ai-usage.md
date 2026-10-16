# AI usage

How much of your coding agents' usage limits you have spent, in the bar and in a panel.

## How it works

The shell does not read any agent's files itself. A small helper program, `pshell-agents`, reads:

- Claude Code's session logs,
- Codex's session files,
- the Fireworks billing API,
- and [opencode](https://github.com/sst/opencode)'s message database.

It writes one JSON file per provider into `~/.local/state/pshell/agents/usage/`. pshell reads those files, watches them for changes, and runs the helper on a timer.

Opening the panel refreshes only the limits (`pshell-agents --limits-only`), and not again within a minute of the last run. The full rescan of session logs stays on the timer. If a limits check fails because the network is not up yet, pshell tries again after 30 seconds, backing off to every 5 minutes.

Without `pshell-agents` on your `PATH`, the widget hides itself instead of showing an error.

## Install the helper

It is the one part of pshell that needs compiling. Build it with Go 1.24 or newer, and put it anywhere on your `PATH`:

```sh
cd ~/.config/quickshell/pshell
go build -o ~/.local/bin/pshell-agents ./cmd/pshell-agents
```

It reads what it finds and skips what it does not, so a source you do not use needs no setup.

### Fireworks

For Fireworks it needs an API key. It looks in this order:

1. the `FIREWORKS_API_KEY` environment variable;
2. firectl's `~/.fireworks/auth.ini` (or the file named by `FIREWORKS_AUTH_PATH`), which `firectl set-api-key` writes;
3. opencode's `auth.json`, if you have signed in to Fireworks in opencode.

The account id comes from `FIREWORKS_ACCOUNT_ID`, then `accountId` in `~/.config/pshell/agents/fireworks.json`, then the same `auth.ini`. You only need to set it when your key can reach more than one account.

### opencode

To read opencode's database it runs `sqlite3`. That database is the only record of a subscription spent entirely through opencode. Without `sqlite3`, the other sources still count, and opencode's are missing.

## Add the widget

```json
{
  "type": "aiUsage",
  "refreshIntervalSec": 900,
  "barSource": "max",
  "warnThreshold": 85,
  "defaultTab": "",
  "hideWhenIdle": false
}
```

| Setting | What it does | Default |
|---|---|---|
| `refreshIntervalSec` | Seconds between full runs of the helper | `900` (15 minutes) |
| `barSource` | What the bar shows. See below. | `max` |
| `warnThreshold` | Percent at which the number turns red | `85` |
| `defaultTab` | A provider id to open the panel on | the provider closest to its limit |
| `hideWhenIdle` | Hide the widget until something has been spent | `false` |
| `width` | Width of the panel, in pixels | `360` |

The providers are whatever files are in the usage folder. A new file means a new tab. There is no list of providers to keep up to date.

## The bar

`barSource` decides what the bar shows:

| Value | What the bar shows |
|---|---|
| `max` | The single tightest limit across every provider, with that provider's logo. This is the number that is about to stop you. |
| a provider id | That provider only |
| `all` | Every provider, tightest first |

The number turns red past `warnThreshold`. A provider that reports no limit at all shows a dash. The tooltip says which limit it is and when it resets.

## The panel

The panel has one tab per provider, each showing only the provider's logo. Left and right arrow keys move between tabs. With no `defaultTab`, the panel opens on the provider closest to its limit, which is the one the bar is already showing.

Each tab shows:

- the provider's name and plan;
- each of its usage limits, with when it resets. Providers report different numbers of these: Claude three, Codex one, Fireworks none. Fireworks bills from a balance, so it has nothing to run out of, and the tab says so.
- seven days of token use, as seven columns. The columns are scaled to the busiest day of the week, not to a fixed number. Today is drawn in the accent colour.
- tokens by model, and today's sessions.

The panel keeps the same width on every tab. Only the height changes.

The files are watched, so each run of the helper updates the panel without anything polling. Opening the panel also runs the helper once.

## Logos

The logos ship in `Widgets/AiUsage/assets/`, named by provider id. They keep their brand colours, since a row of identical grey shapes would be hard to tell apart. Codex's logo is a single colour and ships in light and dark versions, so it follows the theme. A provider with no logo gets a generic icon.
