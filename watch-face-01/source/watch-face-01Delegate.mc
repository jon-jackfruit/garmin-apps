import Toybox.Complications;
import Toybox.Lang;
import Toybox.WatchUi;

// Touch-and-hold on an item opens the Garmin page behind its complication
// (heart rate graph, body battery, sunrise/sunset, battery).
class watch_face_01Delegate extends WatchUi.WatchFaceDelegate {

    private var _view as watch_face_01View;

    function initialize(view as watch_face_01View) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Boolean {
        var xy = clickEvent.getCoordinates();
        var type = _view.complicationAt(xy[0], xy[1]);
        if (type == null) {
            return false;
        }
        try {
            Complications.exitTo(new Complications.Id(type));
            return true;
        } catch (e) {
            return false;
        }
    }
}
