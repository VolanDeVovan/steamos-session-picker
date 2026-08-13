import QtQuick

// The three things the machine itself can be told to do. Drawn the same way
// ui/SessionIcon.qml draws the session icons and for the same reason: only
// qtdeclarative is guaranteed on the target, so no SVG and no icon font — and
// no font means the glyph cannot be a character either.
//
// A fixed 100x100 space, scaled by `k`.
Item {
    id: icon

    property string kind: "sleep" // sleep | restart | poweroff
    property color tint: "#ffffff"
    property real size: 100

    readonly property real k: size / 100

    implicitWidth: size
    implicitHeight: size

    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            const k = icon.k;

            ctx.reset();
            ctx.strokeStyle = icon.tint;
            ctx.fillStyle = icon.tint;
            ctx.lineWidth = 9 * k;
            ctx.lineCap = "round";

            if (icon.kind === "sleep") {
                // A crescent, as one disc with a second taken out of it. The
                // moon is the one shape a room reads as sleep without a word
                // next to it.
                ctx.beginPath();
                ctx.arc(52 * k, 50 * k, 34 * k, 0, Math.PI * 2);
                ctx.fill();
                ctx.globalCompositeOperation = "destination-out";
                ctx.beginPath();
                ctx.arc(74 * k, 32 * k, 32 * k, 0, Math.PI * 2);
                ctx.fill();
                ctx.globalCompositeOperation = "source-over";
            } else if (icon.kind === "restart") {
                // Most of a ring, and an arrowhead where it stops, so it reads
                // as going round rather than as a broken circle.
                ctx.beginPath();
                ctx.arc(50 * k, 52 * k, 31 * k, Math.PI * 1.62, Math.PI * 1.15);
                ctx.stroke();

                const hx = 50 * k + 31 * k * Math.cos(Math.PI * 1.62);
                const hy = 52 * k + 31 * k * Math.sin(Math.PI * 1.62);
                const h = 13 * k;
                ctx.beginPath();
                ctx.moveTo(hx + h, hy - h * 0.2);
                ctx.lineTo(hx - h * 0.5, hy - h * 0.9);
                ctx.lineTo(hx - h * 0.1, hy + h * 0.9);
                ctx.closePath();
                ctx.fill();
            } else if (icon.kind === "poweroff") {
                // IEC 5009, which is on the case of every machine anyone in the
                // room has ever turned off.
                ctx.beginPath();
                ctx.arc(50 * k, 56 * k, 31 * k, Math.PI * 1.72, Math.PI * 1.28);
                ctx.stroke();
                ctx.beginPath();
                ctx.moveTo(50 * k, 14 * k);
                ctx.lineTo(50 * k, 48 * k);
                ctx.stroke();
            }
        }

        // Canvas caches its buffer, so anything that changes the picture has to
        // ask for it again.
        Connections {
            target: icon
            function onTintChanged() {
                canvas.requestPaint();
            }
            function onKChanged() {
                canvas.requestPaint();
            }
            function onKindChanged() {
                canvas.requestPaint();
            }
        }
    }
}
