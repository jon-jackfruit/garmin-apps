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
- **Next alarm:** not shown. Connect IQ doesn't let apps read alarm times (only `DeviceSettings.alarmCount`), and there's no alarm complication.
- **Links:** touch-and-hold on sunrise/sunset, heart rate, body battery or device battery opens the matching Garmin page via `Complications.exitTo` (`source/watch-face-01Delegate.mc`). Garmin only passes touch-and-hold (`WatchFaceDelegate.onPress`) to watch faces, not taps.
- Body battery is a person icon that fills from the bottom with the level. Device battery turns red below 20%.
- **AMOLED always-on mode:** on devices that need burn-in protection (fr165), the screen stays black while the watch is asleep.
