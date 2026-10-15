# Weather

An icon and the temperature in the bar. Click it for feels-like, humidity, wind, the next hours, and three days of highs and lows.

Add the widget to a section, and put its settings in a `weather` block:

```json
{
  "right": [
    { "type": "weather", "showLabel": false }
  ],
  "weather": {
    "location": "Berlin",
    "units": "metric",
    "intervalMin": 15,
    "hourlyHours": 12
  }
}
```

The settings are in their own block rather than on the widget because the shell fetches the weather once, however many screens show a bar.

## Widget settings

| Setting | What it does | Default |
|---|---|---|
| `showLabel` | Show the condition in the bar too | `false` |
| `panelWidth` | Width of the panel, in pixels | `300` |

## Weather settings

| Key | What it does | Default |
|---|---|---|
| `location` | A place name. It is looked up once and remembered. | none |
| `latitude`, `longitude` | Exact coordinates. **These win over `location`.** | none |
| `units` | `metric` or `imperial` | `metric` |
| `intervalMin` | Minutes between refreshes. The lowest is 5. | `15` |
| `hourlyHours` | Hours in the panel's hourly row, counting the current one. At most 24. `0` hides the row. | `12` |

Coordinates win because a place name can be ambiguous. There is more than one Springfield, and the lookup returns the biggest. If you got the wrong one, set the coordinates. If you set both, the name is still used as the label, so the panel says "Cambridge" and the forecast is for the Cambridge you meant.

The lowest refresh interval is five minutes. Open-Meteo is free and needs no account, so pshell does not ask more often than that. Fifteen minutes is also as fine as the data gets, since the forecast itself moves in fifteen-minute steps.

The settings app's Weather page edits the same block, and its buttons run the same code as the commands below.

## Old readings

A reading older than two refresh intervals is dimmed in the bar, and the panel shows a `STALE` label. The panel always says how old the reading is.

The last good reading is saved to disk. A shell started with no network shows the last thing it knew, with its age, instead of nothing.

## The next hours

The panel shows the hours ahead in rows of six. Each has the time, an icon (a moon after sunset at that place), the temperature, and the chance of rain when it is 20% or more. They come in the same request as everything else, and move on at the top of each hour without waiting for a fetch.

The hours start from the current hour where the forecast is for, not where your machine is. A laptop in New York showing Tokyo starts at Tokyo's hour.

The times are 12-hour if your `clock` widget's `format` (or else the `calendar`'s `timeFormat`) has an AM/PM marker in it, and 24-hour otherwise.

One thing to know around a daylight saving change: Open-Meteo labels every hour with the offset in force when it answered. So on the day before the clocks change, the hours after the change are labelled one hour off. Which hour is "now" is still right, and the next fetch after the change fixes the labels.

## What it sends, and to whom

This widget makes network requests to a third party, so here is exactly what it sends.

It talks to [Open-Meteo](https://open-meteo.com), which needs no API key and no account. Two addresses:

- `geocoding-api.open-meteo.com`, once for each `location` you set, and never again while it stays the same. It receives the place name you typed.
- `api.open-meteo.com`, every `intervalMin` minutes while the shell runs. It receives your coordinates, at whatever precision the lookup gave or you wrote, and nothing else. No identifier, no account, no cookie.

If you set `latitude` and `longitude` yourself, the place lookup is never used. Round them off if you would rather not share your street.

Without the widget in your bar, nothing is fetched on a timer. The commands below still work, and `pshell weather refresh` fetches once when you ask. Only `toggle`, `open` and `close` need the widget, since the widget draws the panel.

## Commands

```sh
pshell weather refresh                       # fetch now
pshell weather current                       # one line: temperature, condition, place, age
pshell weather hourly                        # up to the next 24 hours, one line each
pshell weather toggle                        # open or close the panel
pshell weather setLocation Berlin            # look up a new place and fetch
pshell weather setCoordinates 52.52 13.40    # set the exact spot
pshell weather clearCoordinates              # go back to the place name
```

`setLocation` writes the name into `config.json` and clears any coordinates. Otherwise the coordinates would still win and the new name would do nothing.

`setCoordinates` takes both numbers in one call, since a latitude alone is not a place.

`hourly` prints up to 24 hours, whatever `hourlyHours` says, since that setting is about room in the panel. It prints fewer when the last reading is old enough that the forecast runs out. With no reading at all, it prints `error: no hourly forecast yet` and exits with an error.

Each line is the hour, the temperature, the chance of rain, and the condition, separated by two spaces. The condition is last because it can have spaces in it:

```text
21:00  24°C  40%  Light rain
22:00  23°C  10%  Overcast
```

## Files

The last reading is kept in `~/.local/state/pshell/weather.json`. The looked-up coordinates for your `location` are kept in `~/.config/pshell/state.json`. Delete either and it is rebuilt on the next fetch.
