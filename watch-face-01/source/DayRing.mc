import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.UserProfile;

// A 24-hour ring around the face split into 96 15-minute bands. Each band is
// coloured by what most of that 15 minutes was spent doing. Bands sit at
// their clock position (midnight at the top, clockwise) and are filled from
// the most recent bedtime (the sleep time in the user profile) up to now; the
// rest of the ring is left blank. So the ring restarts each night at bedtime.
// Without a configured bedtime it starts at midnight.
//
// Connect IQ has no sleep or stress timeline, so each stress-history sample
// is classified like this:
//   - inside a recorded activity (UserProfile activity history) -> activity
//   - stress <= 25 inside the user's configured sleep window      -> sleep
//   - stress <= 25                                                -> rest
//   - stress > 25                                                 -> stress
//   - no stress value (off-wrist, moving)                         -> no data
//
// The watch only keeps a few hours of stress history, so each rebuild saves
// its bands to Application.Storage and the next one reuses them for any
// quarter the history no longer covers. As long as the face runs at least
// once inside the history window (it redraws every minute while it's the
// current screen), the record covers the whole 24 hours.
class DayRing {

    static const STATE_NONE = 0;
    static const STATE_SLEEP = 1;
    static const STATE_REST = 2;
    static const STATE_STRESS = 3;
    static const STATE_ACTIVE = 4;
    // Outside the bedtime-to-now window: not drawn.
    static const STATE_EMPTY = 5;
    private const STATE_COUNT = 5;

    private const COLORS = [
        0x262626, // no data
        0x7B5CFF, // sleep
        0x2E86DE, // rest
        0xFF8C1A, // stress
        0x34C759  // activity
    ];

    private const BANDS = 96;
    private const BAND_SECONDS = 900;
    private const DAY_SECONDS = 86400;
    private const REST_MAX_STRESS = 25;
    private const BAND_DEGREES = 3.75;

    // Storage: per band [local quarter index, state, sample count], flattened.
    private const STORAGE_KEY = "dayRing";
    private const RECORD_SIZE = 3;

    private var _bands as Array<Number>;

    // Local-time quarter-hour index the bands were last built for.
    private var _builtFor as Number = -1;

    function initialize() {
        _bands = new Array<Number>[BANDS];
        for (var i = 0; i < BANDS; i++) {
            _bands[i] = STATE_NONE;
        }
    }

    // Rebuilds the bands once per 15 minutes; cheap to call on every update.
    function update() as Void {
        var offset = System.getClockTime().timeZoneOffset;
        var nowLocal = Time.now().value() + offset;
        var current = nowLocal / BAND_SECONDS;
        if (current == _builtFor) {
            return;
        }
        _builtFor = current;

        // Bands cover [windowStart, end of the current quarter).
        var windowStart = (current - BANDS + 1) * BAND_SECONDS;
        var activities = loadActivities(windowStart - offset, offset);
        var sleepWindow = loadSleepWindow();

        var counts = new Array<Number>[BANDS * STATE_COUNT];
        for (var i = 0; i < counts.size(); i++) {
            counts[i] = 0;
        }

        if (Toybox has :SensorHistory && SensorHistory has :getStressHistory) {
            var iter = SensorHistory.getStressHistory({
                :period => new Time.Duration(DAY_SECONDS),
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
            var sample = iter.next();
            while (sample != null) {
                var t = sample.when.value() + offset;
                // Don't assume the sample order: the simulator returns oldest first.
                if (t < windowStart) {
                    sample = iter.next();
                    continue;
                }
                var state = classify(t, sample.data, activities, sleepWindow);
                var band = (t / BAND_SECONDS) % BANDS;
                counts[band * STATE_COUNT + state] += 1;
                sample = iter.next();
            }
        }

        var stored = loadRecord();
        var record = new Array<Number>[BANDS * RECORD_SIZE];
        for (var b = 0; b < BANDS; b++) {
            var best = STATE_NONE;
            var bestCount = 0;
            var total = 0;
            for (var s = 0; s < STATE_COUNT; s++) {
                var c = counts[b * STATE_COUNT + s];
                total += c;
                if (s != STATE_NONE && c > bestCount) {
                    best = s;
                    bestCount = c;
                }
            }
            // Only call the band if real data outweighs the gaps.
            var state = bestCount >= counts[b * STATE_COUNT + STATE_NONE] ? best : STATE_NONE;

            // The quarter this slot shows: the most recent one at this clock position.
            var quarter = current - (current - b) % BANDS;

            // Keep the saved result if it came from more samples, e.g. once the
            // history has dropped the start of this quarter or all of it.
            var i = b * RECORD_SIZE;
            if (stored != null && stored[i] == quarter && stored[i + 2] > total) {
                state = stored[i + 1];
                total = stored[i + 2];
            }

            _bands[b] = state;
            record[i] = quarter;
            record[i + 1] = state;
            record[i + 2] = total;
        }
        saveRecord(record);

        // Activities without stress samples (stress isn't measured while
        // moving) still count: mark any band they cover for most of its length.
        for (var i = 0; i < activities.size(); i++) {
            var a = activities[i];
            var first = a[0] / BAND_SECONDS;
            var last = (a[1] - 1) / BAND_SECONDS;
            for (var q = first; q <= last; q++) {
                if (q * BAND_SECONDS < windowStart || q > current) {
                    continue;
                }
                var qs = q * BAND_SECONDS;
                var overlap = min(a[1], qs + BAND_SECONDS) - max(a[0], qs);
                if (overlap * 2 >= BAND_SECONDS) {
                    _bands[q % BANDS] = STATE_ACTIVE;
                }
            }
        }

        // Only show bedtime -> now.
        var ringStart = startQuarter(nowLocal, sleepWindow);
        for (var b = 0; b < BANDS; b++) {
            if (current - (current - b) % BANDS < ringStart) {
                _bands[b] = STATE_EMPTY;
            }
        }
    }

    // Local quarter index the ring starts at: the most recent bedtime, or
    // midnight if no bedtime is configured.
    private function startQuarter(nowLocal as Number, sleepWindow as Array<Number>?) as Number {
        var tod = nowLocal % DAY_SECONDS;
        var start;
        if (sleepWindow == null) {
            start = nowLocal - tod;
        } else {
            var sinceBed = (tod - sleepWindow[0] + DAY_SECONDS) % DAY_SECONDS;
            start = nowLocal - sinceBed;
        }
        return start / BAND_SECONDS;
    }

    private function loadRecord() as Array<Number>? {
        try {
            var value = Application.Storage.getValue(STORAGE_KEY);
            if (value instanceof Array && value.size() == BANDS * RECORD_SIZE) {
                return value as Array<Number>;
            }
        } catch (e) {
            // Storage unavailable or corrupt: start a fresh record.
        }
        return null;
    }

    private function saveRecord(record as Array<Number>) as Void {
        try {
            Application.Storage.setValue(STORAGE_KEY, record as Array<Application.Storage.ValueType>);
        } catch (e) {
            // Out of storage: the ring still works from live history.
        }
    }

    // Draws the ring centred on (cx, cy) with outer radius `outer`.
    function draw(dc as Dc, cx as Number, cy as Number, outer as Number, width as Number) as Void {
        var r = outer - width / 2;
        dc.setPenWidth(width);

        // Draw runs of the same state as one arc.
        var start = 0;
        while (start < BANDS) {
            var state = _bands[start];
            var end = start + 1;
            while (end < BANDS && _bands[end] == state) {
                end++;
            }
            if (state == STATE_EMPTY) {
                start = end;
                continue;
            }
            dc.setColor(COLORS[state] as Number, Graphics.COLOR_TRANSPARENT);
            if (end - start == BANDS) {
                // One state all round: draw as two halves, see arc().
                arc(dc, cx, cy, r, bandAngle(0), bandAngle(BANDS / 2));
                arc(dc, cx, cy, r, bandAngle(BANDS / 2), bandAngle(BANDS));
            } else {
                arc(dc, cx, cy, r, bandAngle(start), bandAngle(end));
            }
            start = end;
        }

        // Thin black notches every 6 hours so the ring reads as a clock.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        for (var q = 0; q < BANDS; q += BANDS / 4) {
            var a = bandAngle(q);
            arc(dc, cx, cy, r, a + 1, a - 1);
        }

        // White tick at the current time.
        var clock = System.getClockTime();
        var minutes = clock.hour * 60 + clock.min;
        var nowAngle = 90 - minutes * 0.25;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        arc(dc, cx, cy, r, nowAngle + 1.5, nowAngle - 1.5);
        dc.setPenWidth(1);
    }

    // Clockwise arc from `from` to `to` degrees. drawArc truncates angles to
    // whole degrees and draws a full circle when they come out equal, so
    // round them here and skip arcs that would collapse to nothing.
    private function arc(dc as Dc, cx as Number, cy as Number, r as Number, from as Numeric, to as Numeric) as Void {
        var a = normalize(Math.round(from).toNumber());
        var b = normalize(Math.round(to).toNumber());
        if (a != b) {
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, a, b);
        }
    }

    private function normalize(deg as Number) as Number {
        var d = deg % 360;
        return d < 0 ? d + 360 : d;
    }

    // Garmin arc angles: 0 = 3 o'clock, counter-clockwise positive. Midnight at the top.
    private function bandAngle(band as Number) as Float {
        return 90 - band * BAND_DEGREES;
    }

    private function classify(t as Number, stress as Numeric?, activities as Array<Array<Number>>,
        sleepWindow as Array<Number>?) as Number {
        for (var i = 0; i < activities.size(); i++) {
            if (t >= activities[i][0] && t < activities[i][1]) {
                return STATE_ACTIVE;
            }
        }
        if (stress == null || stress < 0) {
            return STATE_NONE;
        }
        if (stress > REST_MAX_STRESS) {
            return STATE_STRESS;
        }
        return inSleepWindow(t % DAY_SECONDS, sleepWindow) ? STATE_SLEEP : STATE_REST;
    }

    // Recorded activities as [start, end) in local seconds, newer than `since` (UTC seconds).
    private function loadActivities(since as Number, offset as Number) as Array<Array<Number>> {
        var result = [] as Array<Array<Number>>;
        if (!(Toybox has :UserProfile && UserProfile has :getUserActivityHistory)) {
            return result;
        }
        var iter = UserProfile.getUserActivityHistory();
        var a = iter.next();
        while (a != null) {
            var start = a.startTime;
            var duration = a.duration;
            if (start != null && duration != null) {
                var s = start.value();
                var e = s + duration.value();
                if (e > since) {
                    result.add([s + offset, e + offset]);
                }
            }
            a = iter.next();
        }
        return result;
    }

    // [sleep, wake] as seconds since local midnight, or null if not configured.
    private function loadSleepWindow() as Array<Number>? {
        var profile = UserProfile.getProfile();
        var sleep = profile.sleepTime;
        var wake = profile.wakeTime;
        if (sleep == null || wake == null) {
            return null;
        }
        return [sleep.value() % DAY_SECONDS, wake.value() % DAY_SECONDS];
    }

    private function inSleepWindow(tod as Number, window as Array<Number>?) as Boolean {
        if (window == null) {
            return false;
        }
        var sleep = window[0];
        var wake = window[1];
        if (sleep <= wake) {
            return tod >= sleep && tod < wake;
        }
        return tod >= sleep || tod < wake; // wraps past midnight
    }

    private function min(a as Number, b as Number) as Number {
        return a < b ? a : b;
    }

    private function max(a as Number, b as Number) as Number {
        return a > b ? a : b;
    }
}
