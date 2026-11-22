# Watch Face 01

## Requirements

### Data to show
- 24hr format time
- Current heart-rate
- Current body battery level
- Sunset and sunrise time
- Next alarm


### Styles
- Simple clean fonts,
- Black background
- White text with limited use of color for icons

## Implementation notes

- Everything is drawn in `source/watch-face-01View.mc`; no layout XML. Icons are drawn with primitives so they stay crisp at any resolution.
- Heart rate, body battery, sunrise and sunset come from system complications (needs the `ComplicationSubscriber` permission). Heart rate falls back to `Activity.Info.currentHeartRate`. Missing values show `--`.
- **Next alarm:** Connect IQ doesn't expose alarm times to apps, only `DeviceSettings.alarmCount`. The face shows a bell with the number of alarms set and hides it when there are none.
- **AMOLED always-on mode:** on devices that need burn-in protection (fr165), the screen stays black while the watch is asleep.
