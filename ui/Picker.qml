import QtQuick
import QtQuick.Window
import "theme.js" as Theme
import "sessions.js" as Sessions

// Session picker shown instead of an unconditional autologin into Game Mode.
//
// This file never launches anything. It prints "PICKER_CHOICE:<target>" and
// quits; bin/steam-session-picker reads that line and calls steamosctl. QML has
// no process API, and keeping the system half in shell is cheaper than a C++
// shim — see docs/development.md.
//
// Arguments (optional, passed after `--` to the qml runtime):
//   --sessions=JSON     the list to offer, discovered by bin/picker-session on
//                       the machine. Without it the built-in list is used, so
//                       the UI still runs standalone.
//   --fullscreen        take the whole output; the real session always wants it
//   --size=WxH          window size, for checking the layout at 4K or 720p
//   --select=N          preselect card N (0-based)
//   --launching         render the launch overlay (screenshot aid)
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

    // Everything is sized against a 1920x1080 design, so the layout holds on a
    // 4K television and in a small window alike. Nothing here is in raw pixels.
    readonly property real u: Math.min(width / 1920, height / 1080)

    readonly property real cardWidth: 340 * u
    readonly property real cardHeight: 430 * u
    readonly property real cardGap: 40 * u
    readonly property real focusScale: 1.05

    // What the machine actually offers, when something told us. The built-in
    // list is a fallback for running the UI on its own.
    readonly property var sessions: {
        const supplied = argValue("--sessions=");
        if (supplied === "")
            return Sessions.sessions;
        try {
            const parsed = JSON.parse(supplied);
            return parsed.length > 0 ? parsed : Sessions.sessions;
        } catch (e) {
            console.log("PICKER_WARNING:could not parse --sessions, using the built-in list");
            return Sessions.sessions;
        }
    }

    property int currentIndex: 0
    property bool launching: false
    property string launchingTitle: ""

    width: 1920
    height: 1080
    visible: true
    visibility: hasArg("--fullscreen") ? Window.FullScreen : Window.Windowed
    title: "Session"
    color: Theme.backgroundBottom

    function move(delta) {
        if (launching)
            return;
        const n = sessions.length;
        currentIndex = (currentIndex + delta + n) % n;
    }

    function activate() {
        if (launching)
            return;
        const session = sessions[currentIndex];
        launchingTitle = session.title;
        launching = true;
        // Contract with bin/steam-session-picker. Keep the prefix in sync.
        console.log("PICKER_CHOICE:" + session.target);
        quitTimer.start();
    }

    function cancel() {
        if (launching)
            return;
        console.log("PICKER_CHOICE:none");
        Qt.quit();
    }

    Timer {
        id: quitTimer
        interval: 420
        onTriggered: Qt.quit()
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
            currentIndex = parseInt(preselect);

        if (hasArg("--launching")) {
            launching = true;
            launchingTitle = sessions[currentIndex].title;
        }

        if (argValue("--shot=") !== "")
            shotTimer.start();
    }

    // Dev aid: render to a file and exit, so layout can be reviewed without
    // taking over the display. Runs late enough for animations to settle.
    Timer {
        id: shotTimer
        interval: 900
        onTriggered: content.grabToImage(function (result) {
            result.saveToFile(root.argValue("--shot="));
            Qt.quit();
        })
    }

    Item {
        id: content
        anchors.fill: parent
        focus: true

        Keys.onLeftPressed: root.move(-1)
        Keys.onRightPressed: root.move(1)
        Keys.onReturnPressed: root.activate()
        Keys.onEnterPressed: root.activate()
        Keys.onSpacePressed: root.activate()
        Keys.onEscapePressed: root.cancel()
        Keys.onPressed: function (event) {
            // Number keys as direct shortcuts: 1 = first card, and so on.
            if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.sessions.length) {
                root.currentIndex = event.key - Qt.Key_1;
                root.activate();
                event.accepted = true;
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Theme.backgroundTop
                }
                GradientStop {
                    position: 1.0
                    color: Theme.backgroundBottom
                }
            }
        }

        // --- header ---------------------------------------------------------
        // The label says SteamOS, not the model: the same picker runs on a Steam
        // Machine, a Deck, or anything else the OS is on.
        Text {
            x: 72 * root.u
            y: 56 * root.u
            text: "STEAMOS"
            color: Theme.textFaint
            font.pixelSize: 22 * root.u
            font.weight: Font.DemiBold
            font.letterSpacing: 4 * root.u
        }

        Column {
            x: parent.width - width - 72 * root.u
            y: 52 * root.u
            spacing: 4 * root.u

            Text {
                id: clock
                anchors.right: parent.right
                color: Theme.textMuted
                font.pixelSize: 30 * root.u
                font.weight: Font.DemiBold
                text: Qt.formatTime(new Date(), "HH:mm")
            }

            Text {
                id: today
                anchors.right: parent.right
                color: Theme.textFaint
                font.pixelSize: 18 * root.u
                text: Qt.formatDate(new Date(), "ddd d MMM")
            }

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    const now = new Date();
                    clock.text = Qt.formatTime(now, "HH:mm");
                    today.text = Qt.formatDate(now, "ddd d MMM");
                }
            }
        }

        // --- shelf ----------------------------------------------------------
        // The track slides only when the cards do not all fit, which is what
        // Steam does on a long shelf. With a handful of sessions it stays put
        // and only the highlight travels.
        Item {
            id: viewport
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: root.cardHeight * root.focusScale + 48 * root.u
            clip: true

            Item {
                id: track

                readonly property real step: root.cardWidth + root.cardGap
                readonly property real contentWidth: root.sessions.length * root.cardWidth + (root.sessions.length - 1) * root.cardGap
                readonly property real centeredX: viewport.width / 2 - (root.currentIndex * step + root.cardWidth / 2)

                width: contentWidth
                height: parent.height
                x: contentWidth <= viewport.width ? (viewport.width - contentWidth) / 2 : Math.max(viewport.width - contentWidth, Math.min(0, centeredX))

                Behavior on x {
                    NumberAnimation {
                        duration: 280
                        easing.type: Easing.OutCubic
                    }
                }

                // Focus halo and border travel as one object between cards —
                // the Big Picture feel — instead of cross-fading per card.
                Item {
                    id: highlight

                    readonly property real pad: 7 * root.u

                    width: root.cardWidth * root.focusScale + pad * 2
                    height: root.cardHeight * root.focusScale + pad * 2
                    x: root.currentIndex * track.step + root.cardWidth / 2 - width / 2
                    y: (track.height - height) / 2
                    opacity: root.launching ? 0 : 1

                    Behavior on x {
                        NumberAnimation {
                            duration: 260
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: highlight.pad
                        radius: 12 * root.u * root.focusScale
                        color: "transparent"
                        border.width: 3 * root.u
                        border.color: Theme.accent
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 12 * root.u * root.focusScale + highlight.pad
                        color: "transparent"
                        border.width: 2 * root.u
                        border.color: Theme.accent
                        opacity: 0.35
                    }
                }

                Repeater {
                    model: root.sessions

                    SessionCard {
                        required property var modelData
                        required property int index

                        u: root.u
                        width: root.cardWidth
                        height: root.cardHeight
                        x: index * track.step
                        y: (track.height - height) / 2

                        title: modelData.title
                        subtitle: modelData.subtitle
                        kind: modelData.kind
                        selected: root.currentIndex === index
                        focusScale: root.focusScale

                        onPointerEntered: root.currentIndex = index
                        onActivated: {
                            root.currentIndex = index;
                            root.activate();
                        }
                    }
                }
            }
        }

        // --- footer ---------------------------------------------------------
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - 64 * root.u
            color: Theme.textFaint
            font.pixelSize: 21 * root.u
            text: "←  →   select        Enter   launch        Esc   cancel"
            opacity: root.launching ? 0 : 1
            Behavior on opacity {
                NumberAnimation {
                    duration: 160
                }
            }
        }

        // --- launch overlay -------------------------------------------------
        Rectangle {
            anchors.fill: parent
            color: Theme.backgroundBottom
            opacity: root.launching ? 0.9 : 0
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 260
                }
            }

            Text {
                anchors.centerIn: parent
                text: "Starting " + root.launchingTitle + "…"
                color: Theme.textPrimary
                font.pixelSize: 40 * root.u
                font.weight: Font.DemiBold
            }
        }
    }
}
