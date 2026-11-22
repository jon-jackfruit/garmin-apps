import Toybox.Activity;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Black background, white text, colour only on the icons.
//
//          ☀↑ 06:42   ☀↓ 19:12
//
//               14:37
//
//          ♥ 62        ▮ 78%
//
//              🔔 2
class watch_face_01View extends WatchUi.WatchFace {

    private const COLOR_HEART = 0xFF3B3B;
    private const COLOR_BATTERY = 0x3FA9F5;
    private const COLOR_SUN = 0xFFAA00;
    private const COLOR_ALARM = 0xFFD54A;
    private const NO_DATA = "--";

    private var _isAwake as Boolean = true;
    private var _burnInProtection as Boolean = false;

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

        // AMOLED always-on mode: leave the screen black.
        if (!_isAwake && _burnInProtection) {
            return;
        }

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        // Sunrise / sunset
        var sunY = (h * 0.20).toNumber();
        drawSunItem(dc, cx - (w * 0.20).toNumber(), sunY, true, formatSecondsOfDay(getComplicationNumber(Complications.COMPLICATION_TYPE_SUNRISE)));
        drawSunItem(dc, cx + (w * 0.20).toNumber(), sunY, false, formatSecondsOfDay(getComplicationNumber(Complications.COMPLICATION_TYPE_SUNSET)));

        // Time
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.43).toNumber(), Graphics.FONT_NUMBER_THAI_HOT, getTimeString(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Heart rate / body battery
        var statY = (h * 0.67).toNumber();
        var hr = getHeartRate();
        drawStat(dc, cx - (w * 0.20).toNumber(), statY, :heart, hr != null ? hr.toString() : NO_DATA);

        var bb = getComplicationNumber(Complications.COMPLICATION_TYPE_BODY_BATTERY);
        drawStat(dc, cx + (w * 0.20).toNumber(), statY, :battery, bb != null ? bb.toString() + "%" : NO_DATA);

        // Alarms
        drawAlarm(dc, cx, (h * 0.84).toNumber());
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

    // ---- Drawing --------------------------------------------------------

    // Icon on the left, text on the right; the pair is centred on (x, y).
    private function drawIconText(dc as Dc, x as Number, y as Number, iconW as Number, text as String,
        font as Graphics.FontType) as Number {
        var gap = 8;
        var textW = dc.getTextWidthInPixels(text, font);
        var left = x - (iconW + gap + textW) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + iconW + gap, y, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        return left;
    }

    private function drawStat(dc as Dc, x as Number, y as Number, icon as Symbol, text as String) as Void {
        var iconW = 22;
        var left = drawIconText(dc, x, y, iconW, text, Graphics.FONT_SMALL);
        if (icon == :heart) {
            drawHeart(dc, left, y, iconW);
        } else {
            drawBattery(dc, left, y, iconW, getComplicationNumber(Complications.COMPLICATION_TYPE_BODY_BATTERY));
        }
    }

    private function drawSunItem(dc as Dc, x as Number, y as Number, rising as Boolean, text as String) as Void {
        var iconW = 22;
        var left = drawIconText(dc, x, y, iconW, text, Graphics.FONT_TINY);
        drawSun(dc, left, y, iconW, rising);
    }

    private function drawAlarm(dc as Dc, x as Number, y as Number) as Void {
        var count = System.getDeviceSettings().alarmCount;
        if (count == null || count == 0) {
            return;
        }
        var iconW = 18;
        var left = drawIconText(dc, x, y, iconW, count.toString(), Graphics.FONT_TINY);
        drawBell(dc, left, y, iconW);
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

    private function drawBattery(dc as Dc, left as Number, cy as Number, size as Number, level as Number?) as Void {
        var bodyW = size - 3;
        var bodyH = (size * 0.6).toNumber();
        var top = cy - bodyH / 2;
        dc.setColor(COLOR_BATTERY, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(left, top, bodyW, bodyH, 3);
        dc.fillRectangle(left + bodyW, cy - bodyH / 4, 3, bodyH / 2);
        if (level != null && level > 0) {
            var fillW = ((bodyW - 6) * (level > 100 ? 100 : level) / 100.0).toNumber();
            dc.fillRectangle(left + 3, top + 3, fillW < 1 ? 1 : fillW, bodyH - 6);
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

    private function drawBell(dc as Dc, left as Number, cy as Number, size as Number) as Void {
        var cx = left + size / 2;
        var top = cy - size / 2 + 2;
        var bottom = cy + size / 3;
        dc.setColor(COLOR_ALARM, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, top + size / 4, size / 4 + 1);
        dc.fillPolygon([
            [cx - size / 4 - 1, top + size / 4],
            [cx + size / 4 + 1, top + size / 4],
            [left + size, bottom],
            [left, bottom]
        ]);
        dc.fillCircle(cx, bottom + 2, 2);
    }

    // ---- Data -----------------------------------------------------------

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
