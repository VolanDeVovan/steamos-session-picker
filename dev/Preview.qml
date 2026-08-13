import QtQuick
import QtQuick.Window
import "../ui"
import "../ui/entries.js" as Entries
import "sessions.js" as Sessions

// The picker in a window, for looking at it.
//
// This is a development aid and nothing else: on the machine the picker is
// SDDM's greeter and there is no window anywhere. What it exists for is the two
// things a greeter is a bad place to iterate on — how the layout holds at a
// given size, and how the thing feels under a keyboard, a pointer or a
// controller.
//
//   just run                    a live window
//   just shot NAME              one PNG, with no display at all
//   just shots                  the whole review set
//
// Arguments, passed after `--` to the qml runtime:
//   --fullscreen        take the whole output
//   --size=WxH          window size, for checking the layout at 4K or 720p
//   --select=N          preselect card N (0-based)
//   --launching         render the launch overlay
//   --shot=PATH         grab the scene into PATH and quit; works headless with
//                       QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
Window {
    id: root

    function argValue(prefix) {
        const args = Qt.application.arguments;
        for (var i = 0; i < args.length; i++) {
            if (args[i].indexOf(prefix) === 0)
                return args[i].substring(prefix.length);
        }
        return "";
    }

    function hasArg(name) {
        return Qt.application.arguments.indexOf(name) !== -1;
    }

    width: 1920
    height: 1080
    visible: true
    visibility: hasArg("--fullscreen") ? Window.FullScreen : Window.Windowed
    title: "Session"
    color: "#0e141b"

    Picker {
        id: picker
        anchors.fill: parent

        // A fixture, not a machine's real list — see dev/sessions.js. In the
        // greeter this comes from SDDM's own sessionModel.
        sessions: Entries.build(Sessions.sessions)

        // Nothing is started from here: there is no session to start into and
        // no SDDM to ask. Choosing a card shows the launch overlay, which is
        // the state worth looking at, and stops there.
        onActivated: function (index) {
            console.log("picker: would start " + root.picker.sessions[index].file);
        }
    }

    Component.onCompleted: {
        const size = argValue("--size=");
        if (size !== "") {
            const parts = size.split("x");
            width = parseInt(parts[0]);
            height = parseInt(parts[1]);
        }

        const preselect = argValue("--select=");
        if (preselect !== "")
            picker.currentIndex = parseInt(preselect);

        if (hasArg("--launching")) {
            picker.launching = true;
            picker.launchingTitle = picker.sessions[picker.currentIndex].title;
        }

        if (argValue("--shot=") !== "")
            shotTimer.start();
    }

    // Render to a file and exit, so layout can be reviewed without taking over
    // the display. Runs late enough for the animations to settle.
    Timer {
        id: shotTimer
        interval: 900
        onTriggered: picker.grabToImage(function (result) {
            result.saveToFile(root.argValue("--shot="));
            Qt.quit();
        })
    }
}
