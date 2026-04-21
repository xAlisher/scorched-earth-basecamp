import QtQuick 2.15
import QtQuick.Layouts 1.15

// Turn log strip — shows last 8 turns, newest on the left.
Rectangle {
    id: panel
    width: parent ? parent.width : 960
    height: 100
    color: "#0a0a0a"

    property var turnLog: []

    // ── palette ──────────────────────────────────────────────────────────────
    readonly property string colP1:     "#ffdd00"
    readonly property string colP2:     "#ff4444"
    readonly property string colMuted:  "#444444"
    readonly property string colAccent: "#00ff41"
    readonly property string colBorder: "#1a1a1a"

    // top border
    Rectangle {
        anchors.top:   parent.top
        width:         parent.width
        height:        1
        color:         panel.colBorder
    }

    // header
    Text {
        id: header
        x: 8; y: 6
        text: "TURN LOG"
        color: panel.colMuted
        font.pixelSize: 10
        font.family: "monospace"
        font.bold: true
        font.letterSpacing: 2
    }

    // entries row
    Row {
        x: 8
        y: header.height + 10
        spacing: 12

        Repeater {
            model: panel.turnLog.length

            delegate: Rectangle {
                width:  108
                height: 68
                color:  "#111111"
                border.color: panel.turnLog[index].player === 1 ? panel.colP1 : panel.colP2
                border.width: 1
                radius: 2

                Column {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 3

                    // T# P#
                    Row {
                        spacing: 6
                        Text {
                            text: "T" + panel.turnLog[index].turn
                            color: panel.colMuted
                            font.pixelSize: 10
                            font.family: "monospace"
                        }
                        Text {
                            text: "P" + panel.turnLog[index].player
                            color: panel.turnLog[index].player === 1 ? panel.colP1 : panel.colP2
                            font.pixelSize: 10
                            font.family: "monospace"
                            font.bold: true
                        }
                    }

                    // angle / power
                    Text {
                        text: panel.turnLog[index].angle + "° " + panel.turnLog[index].power + "pw"
                        color: "#888888"
                        font.pixelSize: 10
                        font.family: "monospace"
                    }

                    // outcome
                    Text {
                        text: panel.turnLog[index].outcome
                        color: {
                            var o = panel.turnLog[index].outcome
                            if (o === "miss")           return panel.colMuted
                            if (o.indexOf("HIT") === 0) return "#ffaa00"
                            return panel.colAccent
                        }
                        font.pixelSize: 10
                        font.family: "monospace"
                        font.bold: panel.turnLog[index].outcome !== "miss"
                    }
                }
            }
        }
    }
}
