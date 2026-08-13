import QtQuick
import "theme.js" as Theme

// The shelf: what the room actually looks at.
//
// A plain Item, and deliberately ignorant — it launches nothing and knows
// nothing about SDDM, sessions or the system. It is handed a list and it emits
// an index; whoever created it acts on that. On the machine that is
// themes/steamos-session-picker/Main.qml, and during development it is
// dev/Preview.qml, which is how the same pixels can be reviewed without a
// greeter.
Item {
    id: root

    // What to show. Cards, as ui/entries.js builds them: title, subtitle, kind.
    property var sessions: []

    property int currentIndex: 0

    // Held while the chosen session starts. In the greeter that is the last
    // thing on screen before the compositor changes hands, so it stays up until
    // the process is killed; nothing here decides when it ends.
    property bool launching: false
    property string launchingTitle: ""

    // Whether Esc means anything. In the greeter it does not: this is the first
    // thing after the firmware and there is nowhere to go back to.
    property bool cancellable: false

    // Which input the room is actually using. A controller offers both at once —
    // the Steam Controller's right trackpad is a mouse — so a thumb resting on
    // it would otherwise fight the d-pad for the selection, and the cursor would
    // sit on the television for the whole time. Whichever was used last wins,
    // and the cursor is hidden while it is not the pointer.
    property bool pointerActive: false

    // Where the pointer was last seen to genuinely be, in scene coordinates.
    // One baseline for the whole shelf, and scene coordinates rather than any
    // card's own, because those two things are what make "did it move?"
    // answerable at all:
    //
    //   * the compositor delivers a motion event for the cursor it parks in the
    //     middle of the screen at startup, so the first event can never count;
    //   * a card scales when the selection reaches it, and that moves the card
    //     *under* a stationary cursor. In the card's own coordinates the pointer
    //     has then "moved" — so with a cursor resting on a card, every d-pad
    //     press handed the selection straight back to the card under it and the
    //     shelf could not be driven at all. Observed on the machine.
    //
    // In scene coordinates a cursor nobody is touching stays exactly where it
    // is, however much the shelf rearranges itself underneath.
    property real pointerX: -1
    property real pointerY: -1

    // True when this hover event means the pointer really moved, which is also
    // the moment the pointer takes the room back from the keys.
    function notePointer(scenePos) {
        if (pointerX < 0 || Math.abs(scenePos.x - pointerX) + Math.abs(scenePos.y - pointerY) > 8 * u) {
            const moved = pointerX >= 0;
            pointerX = scenePos.x;
            pointerY = scenePos.y;
            if (moved)
                pointerActive = true;
            return moved;
        }
        return false;
    }

    signal activated(int index)
    signal cancelled

    // Everything is sized against a 1920x1080 design, so the layout holds on a
    // 4K television and in a small window alike. Nothing here is in raw pixels.
    readonly property real u: Math.min(width / 1920, height / 1080)

    readonly property real cardWidth: 340 * u
    readonly property real cardHeight: 430 * u
    readonly property real cardGap: 40 * u
    readonly property real focusScale: 1.05

    focus: true

    function move(delta) {
        if (launching || sessions.length === 0)
            return;
        const n = sessions.length;
        currentIndex = (currentIndex + delta + n) % n;
    }

    function activate() {
        if (launching || sessions.length === 0)
            return;
        launchingTitle = sessions[currentIndex].title;
        launching = true;
        activated(currentIndex);
    }

    Keys.onLeftPressed: root.move(-1)
    Keys.onRightPressed: root.move(1)
    Keys.onReturnPressed: root.activate()
    Keys.onEnterPressed: root.activate()
    Keys.onSpacePressed: root.activate()
    Keys.onEscapePressed: {
        if (root.cancellable && !root.launching)
            root.cancelled();
    }
    Keys.onPressed: function (event) {
        // Any key means the pointer is not what is being used.
        root.pointerActive = false;

        // Number keys as direct shortcuts: 1 = first card, and so on.
        if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.sessions.length) {
            root.currentIndex = event.key - Qt.Key_1;
            root.activate();
            event.accepted = true;
        }
    }

    // Keeps the cursor hidden between the cards as well, and reports movement
    // there through the same baseline.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: root.pointerActive ? Qt.ArrowCursor : Qt.BlankCursor

        onPositionChanged: function (mouse) {
            root.notePointer(mapToItem(null, mouse.x, mouse.y));
        }
    }

    Rectangle {
        anchors.fill: parent
        z: -1
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

    // --- header -------------------------------------------------------------
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

    // --- shelf --------------------------------------------------------------
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

            // Only animated when the row is longer than the screen and has
            // somewhere to slide. When it fits, the resting position is
            // centred and must simply be obeyed: inside gamescope the window
            // learns its size late, and an animation caught mid-flight left
            // the first card hanging off the left edge.
            Behavior on x {
                enabled: track.contentWidth > viewport.width
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
                opacity: root.launching || root.sessions.length === 0 ? 0 : 1

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
                    pointerActive: root.pointerActive

                    onHovered: function (scenePos) {
                        if (root.notePointer(scenePos))
                            root.currentIndex = index;
                    }
                    onActivated: {
                        root.currentIndex = index;
                        root.activate();
                    }
                }
            }
        }
    }

    // --- footer -------------------------------------------------------------
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 64 * root.u
        color: Theme.textFaint
        font.pixelSize: 21 * root.u
        text: root.cancellable ? "←  →   select        Enter   launch        Esc   cancel" : "←  →   select        Enter   launch"
        opacity: root.launching ? 0 : 1
        Behavior on opacity {
            NumberAnimation {
                duration: 160
            }
        }
    }

    // --- launch overlay -----------------------------------------------------
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

        Column {
            anchors.centerIn: parent
            spacing: 34 * root.u

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Starting " + root.launchingTitle + "…"
                color: Theme.textPrimary
                font.pixelSize: 40 * root.u
                font.weight: Font.DemiBold
            }

            // Indeterminate on purpose. How long a session takes to come up
            // is not known — it depends on what is being started and what
            // the machine was doing — and a bar that fills at a made-up rate
            // is a bar that lies, then sits at the end waiting. This one only
            // claims that something is happening, which is true.
            Rectangle {
                id: progressTrack
                anchors.horizontalCenter: parent.horizontalCenter
                width: 420 * root.u
                height: 6 * root.u
                radius: height / 2
                color: Theme.outline
                clip: true

                Rectangle {
                    id: progressBead
                    width: parent.width * 0.32
                    height: parent.height
                    radius: height / 2
                    color: Theme.accent

                    SequentialAnimation on x {
                        running: root.launching
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: -progressBead.width
                            to: progressTrack.width
                            duration: 1150
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }
        }
    }

    // --- message ------------------------------------------------------------
    // Only ever shown when something the room cannot see went wrong — a session
    // that refused to start, a login PAM turned down. Silent otherwise.
    property string message: ""

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - 110 * root.u
        color: Theme.accent
        font.pixelSize: 22 * root.u
        text: root.message
        opacity: root.message === "" || root.launching ? 0 : 1
        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
    }
}
