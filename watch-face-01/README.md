# Watch Face 01

## Requirements

### Data to show
- 24hr format time
- Current heart-rate
- Current body battery level
- Sunset and sunrise time
- Current day and date (e.g. `SUN 22-11-2026`)
- 24hr ring around the face in 15min bands, each coloured by what most of that 15min was: sleep, rest, stress or activity, from bedtime the night before up to now


### Styles
- Simple clean fonts,
- Black background
- White text with limited use of color for icons

## Implementation notes

- Everything is drawn in `source/watch-face-01View.mc`; no layout XML. Icons are drawn with primitives so they stay crisp at any resolution.
- Heart rate, body battery, sunrise and sunset come from system complications (needs the `ComplicationSubscriber` permission). Heart rate falls back to `Activity.Info.currentHeartRate`. Missing values show `--`.
- **Next alarm:** not shown. Connect IQ doesn't let apps read alarm times (only `DeviceSettings.alarmCount`), and there's no alarm complication.
- **Links:** touch-and-hold on sunrise/sunset, heart rate, body battery or device battery opens the matching Garmin page via `Complications.exitTo` (`source/watch-face-01Delegate.mc`). Garmin only passes touch-and-hold (`WatchFaceDelegate.onPress`) to watch faces, not taps.
- Body battery is a person icon that fills from the bottom with the level. Device battery turns red below 20%.
- **AMOLED always-on mode:** on devices that need burn-in protection (fr165), the screen stays black while the watch is asleep.
- **Day ring** (`source/DayRing.mc`): 96 15-minute bands at their clock position (midnight at the top, clockwise), filled from the most recent bedtime (the user profile's sleep time, or midnight if none is set) up to now. The rest of the ring is blank, so it restarts each night at bedtime. A white tick marks now and black notches mark every 6 hours. Connect IQ has no sleep or stress timeline, so each stress-history sample is classified: inside a recorded activity → activity (green); stress ≤ 25 inside the sleep window set in the user profile → sleep (purple); stress ≤ 25 → rest (blue); stress > 25 → stress (orange); no value → no data (grey). A band takes its most common state, and any band that a recorded activity covers for at least half its length is shown as activity. The bands are rebuilt once per 15 minutes. This needs the `SensorHistory` and `UserProfile` permissions. Each rebuild saves the bands to `Application.Storage` (key `dayRing`: quarter-hour index, state and sample count per band). The next rebuild keeps a saved band when it came from more samples than the live history still has, so the ring fills the full 24 hours even though the watch only keeps a few hours of stress history. The record also keeps updating while the AMOLED screen is blank.
