import QtQuick

// Icons are drawn from primitives instead of SVG files on purpose: everything
// used here lives in qtdeclarative, so the picker needs no image-format plugin
// on the target (SteamOS ships qt6-declarative, nothing else is guaranteed).
//
// Children are laid out in a fixed 100x100 space and scaled by `k`.
Item {
    id: icon

    property string kind: "game"
    property color tint: "#ffffff"
    property real size: 100

    readonly property real k: size / 100

    implicitWidth: size
    implicitHeight: size

    // --- Game Mode: gamepad -------------------------------------------------
    Item {
        anchors.fill: parent
        visible: icon.kind === "game"

        // A rounded body rather than a stadium: a full pill reads as a handheld.
        Rectangle {
            x: 4 * icon.k
            y: 30 * icon.k
            width: 92 * icon.k
            height: 44 * icon.k
            radius: 16 * icon.k
            color: "transparent"
            border.width: 6 * icon.k
            border.color: icon.tint
        }
        // d-pad, centred on (28, 52)
        Rectangle {
            x: 17 * icon.k
            y: 49 * icon.k
            width: 22 * icon.k
            height: 6 * icon.k
            radius: 3 * icon.k
            color: icon.tint
        }
        Rectangle {
            x: 25 * icon.k
            y: 41 * icon.k
            width: 6 * icon.k
            height: 22 * icon.k
            radius: 3 * icon.k
            color: icon.tint
        }
        // face buttons
        Rectangle {
            x: 61 * icon.k
            y: 41 * icon.k
            width: 10 * icon.k
            height: 10 * icon.k
            radius: 5 * icon.k
            color: icon.tint
        }
        Rectangle {
            x: 73 * icon.k
            y: 53 * icon.k
            width: 10 * icon.k
            height: 10 * icon.k
            radius: 5 * icon.k
            color: icon.tint
        }
    }

    // --- Desktop: monitor ---------------------------------------------------
    Item {
        anchors.fill: parent
        visible: icon.kind === "desktop"

        Rectangle {
            x: 10 * icon.k
            y: 16 * icon.k
            width: 80 * icon.k
            height: 56 * icon.k
            radius: 8 * icon.k
            color: "transparent"
            border.width: 6 * icon.k
            border.color: icon.tint
        }
        Rectangle {
            x: 44 * icon.k
            y: 72 * icon.k
            width: 12 * icon.k
            height: 9 * icon.k
            color: icon.tint
        }
        Rectangle {
            x: 28 * icon.k
            y: 81 * icon.k
            width: 44 * icon.k
            height: 6 * icon.k
            radius: 3 * icon.k
            color: icon.tint
        }
    }

    // --- Media: play in a ring ----------------------------------------------
    Item {
        anchors.fill: parent
        visible: icon.kind === "media"

        Rectangle {
            x: 11 * icon.k
            y: 11 * icon.k
            width: 78 * icon.k
            height: 78 * icon.k
            radius: 39 * icon.k
            color: "transparent"
            border.width: 6 * icon.k
            border.color: icon.tint
        }
        Canvas {
            id: playCanvas
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.fillStyle = icon.tint;
                ctx.beginPath();
                ctx.moveTo(41 * icon.k, 34 * icon.k);
                ctx.lineTo(41 * icon.k, 66 * icon.k);
                ctx.lineTo(69 * icon.k, 50 * icon.k);
                ctx.closePath();
                ctx.fill();
            }
            // Canvas caches its buffer, so a tint or size change needs a repaint.
            Connections {
                target: icon
                function onTintChanged() {
                    playCanvas.requestPaint();
                }
                function onKChanged() {
                    playCanvas.requestPaint();
                }
            }
        }
    }
}
