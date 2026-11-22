import Toybox.Activity;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Black background, white text, colour only on the icons and the day ring.
//
//        ╭──── 24h activity ring ────╮
//          ☀↑ 06:42   ☀↓ 19:12
//
//               14:37
//
//          SUN 22-11-2026
//
//          ♥ 62        🧍 78%
//               ▮ 85%
//        ╰───────────────────────────╯
//
// Touch-and-hold an item to open the matching Garmin page (see watch_face_01Delegate).
class watch_face_01View extends WatchUi.WatchFace {

    private const COLOR_HEART = 0xFF3B3B;
    private const COLOR_BODY_BATTERY = 0x3FA9F5;
    private const COLOR_BODY_BATTERY_EMPTY = 0x1B3A52;
    private const COLOR_SUN = 0xFFAA00;
    private const COLOR_DEVICE_BATTERY = 0x4CD964;
    private const COLOR_DEVICE_BATTERY_LOW = 0xFF3B3B;
    private const NO_DATA = "--";
    private const ICON_GAP = 8;
    private const HIT_PAD = 14;
    private const RING_WIDTH = 6;

    private var _ring as DayRing = new DayRing();

    private var _isAwake as Boolean = true;
    private var _burnInProtection as Boolean = false;

    // Touch targets from the last draw: [left, top, right, bottom, complication type].
    private var _hits as Array<Array<Number>> = [];

    function initialize() {
        WatchFace.initialize();
        var settings = System.getDeviceSettings();
        _burnInProtection = settings has :requiresBurnInProtection && settings.requiresBurnInProtection;
    }

    function onLayout(dc as Dc) as Void {
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        _hits = [];

        // Keep the day ring's record going even while the screen is blank.
        _ring.update();

        // AMOLED always-on mode: leave the screen black.
        if (!_isAwake && _burnInProtection) {
            return;
        }

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var colOffset = (w * 0.20).toNumber();

        // 24h ring of 15-minute bands around the edge
        _ring.draw(dc, cx, h / 2, (w < h ? w : h) / 2, RING_WIDTH);

        // Sunrise / sunset, small and close together above the time
        var sunY = (h * 0.22).toNumber();
        var sunOffset = (w * 0.15).toNumber();
        drawItem(dc, cx - sunOffset, sunY, :sunrise, 18,
            formatSecondsOfDay(getComplicationNumber(Complications.COMPLICATION_TYPE_SUNRISE)),
            Graphics.FONT_XTINY, Complications.COMPLICATION_TYPE_SUNRISE);
        drawItem(dc, cx + sunOffset, sunY, :sunset, 18,
            formatSecondsOfDay(getComplicationNumber(Complications.COMPLICATION_TYPE_SUNSET)),
            Graphics.FONT_XTINY, Complications.COMPLICATION_TYPE_SUNSET);

        // Time with the day and date below it, centred as a block
        var timeFont = Graphics.FONT_NUMBER_MEDIUM;
        var dateFont = Graphics.FONT_TINY;
        var timeH = Graphics.getFontAscent(timeFont);
        var dateH = Graphics.getFontAscent(dateFont);
        var dateGap = 26;
        var blockTop = (h * 0.45).toNumber() - (timeH + dateGap + dateH) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, blockTop + timeH / 2, timeFont, getTimeString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, blockTop + timeH + dateGap + dateH / 2, dateFont, getDateString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Heart rate / body battery, just above the device battery
        var statY = (h * 0.73).toNumber();
        var hr = getHeartRate();
        drawItem(dc, cx - colOffset, statY, :heart, 22, hr != null ? hr.toString() : NO_DATA,
            Graphics.FONT_SMALL, Complications.COMPLICATION_TYPE_HEART_RATE);
        var bb = getComplicationNumber(Complications.COMPLICATION_TYPE_BODY_BATTERY);
        drawItem(dc, cx + colOffset, statY, :person, 16, bb != null ? bb.toString() + "%" : NO_DATA,
            Graphics.FONT_SMALL, Complications.COMPLICATION_TYPE_BODY_BATTERY);

        // Device battery, at the bottom of the space inside the ring
        drawDeviceBatteryItem(dc, cx, (h * 0.87).toNumber());
    }

    function onShow() as Void {
    }

    function onHide() as Void {
    }

    function onExitSleep() as Void {
        _isAwake = true;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _isAwake = false;
        WatchUi.requestUpdate();
    }

    // The complication type under (x, y), or null.
    function complicationAt(x as Number, y as Number) as Complications.Type? {
        for (var i = 0; i < _hits.size(); i++) {
            var r = _hits[i];
            if (x >= r[0] && x <= r[2] && y >= r[1] && y <= r[3]) {
                return r[4] as Complications.Type;
            }
        }
        return null;
    }

    // ---- Layout ---------------------------------------------------------

    // Icon on the left, text on the right; the pair is centred on (x, y).
    private function drawItem(dc as Dc, x as Number, y as Number, icon as Symbol, iconW as Number,
        text as String, font as Graphics.FontType, link as Complications.Type?) as Void {
        var textW = dc.getTextWidthInPixels(text, font);
        var totalW = iconW + ICON_GAP + textW;
        var left = x - totalW / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + iconW + ICON_GAP, y, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawIcon(dc, icon, left, y, iconW);

        if (link != null) {
            var half = dc.getFontHeight(font) / 2;
            _hits.add([left - HIT_PAD, y - half - HIT_PAD, left + totalW + HIT_PAD, y + half + HIT_PAD, link as Number]);
        }
    }

    private function drawDeviceBatteryItem(dc as Dc, cx as Number, y as Number) as Void {
        var battery = System.getSystemStats().battery.toNumber();
        drawItem(dc, cx, y, :deviceBattery, 22, battery.toString() + "%", Graphics.FONT_TINY,
            Complications.COMPLICATION_TYPE_BATTERY);
    }

    private function drawIcon(dc as Dc, icon as Symbol, left as Number, cy as Number, size as Number) as Void {
        if (icon == :heart) {
            drawHeart(dc, left, cy, size);
        } else if (icon == :person) {
            drawPerson(dc, left, cy, size, getComplicationNumber(Complications.COMPLICATION_TYPE_BODY_BATTERY));
        } else if (icon == :sunrise) {
            drawSun(dc, left, cy, size, true);
        } else if (icon == :sunset) {
            drawSun(dc, left, cy, size, false);
        } else if (icon == :deviceBattery) {
            drawDeviceBattery(dc, left, cy, size);
        }
    }

    // ---- Icons (drawn with primitives so they scale and stay crisp) -----

    private function drawHeart(dc as Dc, left as Number, cy as Number, size as Number) as Void {
        var r = size / 4;
        var top = cy - size / 4;
        dc.setColor(COLOR_HEART, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(left + r, top + 1, r + 1);
        dc.fillCircle(left + size - r, top + 1, r + 1);
        dc.fillPolygon([
            [left - 1, top + 3],
            [left + size + 1, top + 3],
            [left + size / 2, cy + size / 2]
        ]);
    }

    // Head and shoulders; fills bottom-up with the body battery level.
    private function drawPerson(dc as Dc, left as Number, cy as Number, size as Number, level as Number?) as Void {
        var height = (size * 1.6).toNumber();
        var top = cy - height / 2;
        var headR = size / 4 + 1;
        var bodyTop = top + headR * 2 + 2;

        drawPersonShape(dc, left, top, size, height, headR, bodyTop, COLOR_BODY_BATTERY_EMPTY);
        if (level != null && level > 0) {
            var pct = level > 100 ? 100 : level;
            var filled = (height * pct / 100.0).toNumber();
            dc.setClip(left - 1, top + height - filled, size + 2, filled + 1);
            drawPersonShape(dc, left, top, size, height, headR, bodyTop, COLOR_BODY_BATTERY);
            dc.clearClip();
        }
    }

    private function drawPersonShape(dc as Dc, left as Number, top as Number, size as Number, height as Number,
        headR as Number, bodyTop as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(left + size / 2, top + headR, headR);
        dc.fillRoundedRectangle(left, bodyTop, size, top + height - bodyTop, size / 3);
    }

    private function drawDeviceBattery(dc as Dc, left as Number, cy as Number, size as Number) as Void {
        var level = System.getSystemStats().battery;
        var bodyW = size - 3;
        var bodyH = (size * 0.55).toNumber();
        var top = cy - bodyH / 2;
        dc.setColor(level < 20 ? COLOR_DEVICE_BATTERY_LOW : COLOR_DEVICE_BATTERY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(left, top, bodyW, bodyH, 3);
        dc.fillRectangle(left + bodyW, cy - bodyH / 4, 3, bodyH / 2);
        var fillW = ((bodyW - 6) * (level > 100 ? 100 : level) / 100.0).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(left + 3, top + 3, fillW, bodyH - 6);
        }
        dc.setPenWidth(1);
    }

    // Half sun on a horizon line with an up/down arrow above it.
    private function drawSun(dc as Dc, left as Number, cy as Number, size as Number, rising as Boolean) as Void {
        var cx = left + size / 2;
        var horizon = cy + size / 4;
        var r = size / 3;
        dc.setColor(COLOR_SUN, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(cx, horizon, r, Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawLine(left, horizon, left + size, horizon);
        var tip = cy - size / 2;
        var base = cy - size / 4 + 1;
        if (rising) {
            dc.fillPolygon([[cx, tip], [cx - 4, base], [cx + 4, base]]);
        } else {
            dc.fillPolygon([[cx, base], [cx - 4, tip], [cx + 4, tip]]);
        }
        dc.setPenWidth(1);
    }

    // ---- Data -----------------------------------------------------------

    // e.g. "SUN 22-11-2026"
    private function getDateString() as String {
        var now = Time.now();
        var day = Gregorian.info(now, Time.FORMAT_MEDIUM).day_of_week as String;
        var d = Gregorian.info(now, Time.FORMAT_SHORT);
        return day.toUpper() + " " + d.day.format("%02d") + "-" + (d.month as Number).format("%02d") + "-" + d.year;
    }

    private function getTimeString() as String {
        var t = System.getClockTime();
        return t.hour.format("%02d") + ":" + t.min.format("%02d");
    }

    private function getHeartRate() as Number? {
        var hr = getComplicationNumber(Complications.COMPLICATION_TYPE_HEART_RATE);
        if (hr == null) {
            var info = Activity.getActivityInfo();
            if (info != null) {
                hr = info.currentHeartRate;
            }
        }
        return hr;
    }

    private function getComplicationNumber(type as Complications.Type) as Number? {
        try {
            var value = Complications.getComplication(new Complications.Id(type)).value;
            if (value instanceof Number) {
                return value;
            }
            if (value instanceof Float || value instanceof Double || value instanceof Long) {
                return value.toNumber();
            }
        } catch (e) {
            // Complication not available on this device.
        }
        return null;
    }

    private function formatSecondsOfDay(seconds as Number?) as String {
        if (seconds == null) {
            return NO_DATA;
        }
        return (seconds / 3600).format("%02d") + ":" + ((seconds % 3600) / 60).format("%02d");
    }
}
