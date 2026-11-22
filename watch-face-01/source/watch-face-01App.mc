import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class watch_face_01App extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new watch_face_01View();
        return [ view, new watch_face_01Delegate(view) ];
    }

}

function getApp() as watch_face_01App {
    return Application.getApp() as watch_face_01App;
}