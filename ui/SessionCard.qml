import QtQuick
import "theme.js" as Theme

// One shelf card. The focus border and halo are NOT drawn here — Picker.qml
// owns a single highlight that slides between cards, which is how Big Picture
// moves focus. This item only reacts: it lifts and its contents light up.
Item {
    id: card

    property string title: ""
    property string subtitle: ""
    property string kind: "game"
    property bool selected: false
    property bool pointerActive: true
    property real focusScale: 1.05

    // Layout unit: 1.0 means "designed for 1920x1080". See Picker.qml.
    property real u: 1

    signal activated
    signal pointerEntered

    implicitWidth: 340 * u
    implicitHeight: 430 * u

    scale: selected ? focusScale : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: 260
            easing.type: Easing.OutBack
            easing.overshoot: 1.1
        }
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: 12 * card.u
        color: card.selected ? Theme.surfaceFocused : Theme.surface
        border.width: 1 * card.u
        border.color: Theme.outline

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 26 * card.u

            SessionIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                kind: card.kind
                size: 144 * card.u
                tint: card.selected ? Theme.accent : Theme.iconIdle
                Behavior on tint {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }

            // Titles come from whatever desktop entries the machine has, so they
            // are bounded and elided rather than trusted to fit.
            Text {
                width: card.width - 32 * card.u
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: card.title
                color: card.selected ? Theme.textFocused : Theme.textPrimary
                font.pixelSize: 36 * card.u
                font.weight: Font.DemiBold
                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }

            Text {
                width: card.width - 32 * card.u
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: card.subtitle
                color: Theme.textMuted
                font.pixelSize: 20 * card.u
            }
        }
    }

    MouseArea {
        id: pointer

        // Where the pointer was first seen on this card. Selection follows the
        // pointer, but only once it has really moved: on a television the cursor
        // starts parked in the middle of the screen, and the compositor delivers
        // a motion event for it, which would otherwise hand the selection to
        // whichever card happens to sit under it before anyone touches anything.
        property real originX: -1
        property real originY: -1

        anchors.fill: parent
        hoverEnabled: true
        // The cursor is hidden while the room is driving with keys or a pad.
        cursorShape: card.pointerActive ? Qt.PointingHandCursor : Qt.BlankCursor

        onPositionChanged: function (mouse) {
            if (originX < 0) {
                originX = mouse.x;
                originY = mouse.y;
                return;
            }
            if (Math.abs(mouse.x - originX) + Math.abs(mouse.y - originY) > 8 * card.u)
                card.pointerEntered();
        }
        onExited: {
            originX = -1;
            originY = -1;
        }
        onClicked: card.activated()
    }
}
