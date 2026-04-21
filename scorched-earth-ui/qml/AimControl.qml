import QtQuick 2.15
import QtQuick.Layouts 1.15

Item {
    id: aimRoot
    width: parent.width
    height: 100

    // ── properties ──────────────────────────────────────────────────────────
    property bool myTurn:      false
    property int  gamePhase:   0
    property int  activePlayer: 1
    property real aimAngle:    0
    property real aimPower:    50

    signal fireClicked()

    readonly property bool controlsEnabled: myTurn && gamePhase === 1

    // ── palette ─────────────────────────────────────────────────────────────
    readonly property color colSurface: "#111111"
    readonly property color colAccent:  activePlayer === 1 ? "#ffdd00" : "#ff4444"
    readonly property color colHover:   activePlayer === 1 ? "#2a2a00" : "#2a0000"
    readonly property color colBase:    activePlayer === 1 ? "#1a1a00" : "#1a0000"
    readonly property color colMuted:   "#444444"
    readonly property color colText:    "#c0c0c0"

    // ── layout ───────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: aimRoot.colSurface

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            // Angle row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    property int a: Math.round(aimRoot.aimAngle)
                    text: "> ANGLE: " + (a >= 0 ? "+" : "-") + ("00" + Math.abs(a)).slice(-2) + "°"
                    color: aimRoot.colAccent
                    font.pixelSize: 12
                    font.family: "monospace"
                    Layout.preferredWidth: 130
                }

                Item {
                    id: angleTrack
                    Layout.fillWidth:       true
                    Layout.preferredHeight: 16
                    opacity: aimRoot.controlsEnabled ? 1.0 : 0.35

                    // background
                    Rectangle { anchors.fill: parent; color: "#1a1a1a"; radius: 2 }

                    // fill: extends from center left (negative) or right (positive)
                    Rectangle {
                        property real ratio: aimRoot.aimAngle / 90   // -1..+1
                        x:     ratio >= 0 ? angleTrack.width / 2
                                          : angleTrack.width / 2 + ratio * (angleTrack.width / 2)
                        width: Math.abs(ratio) * (angleTrack.width / 2)
                        height: parent.height
                        color: aimRoot.colAccent
                        radius: 2
                    }

                    // center marker
                    Rectangle {
                        x:      angleTrack.width / 2 - 1
                        width:  2
                        height: parent.height
                        color:  "#555"
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: aimRoot.controlsEnabled
                        onPressed: {
                            var ratio = (mouseX / width - 0.5) * 2
                            aimRoot.aimAngle = Math.max(-90, Math.min(90, Math.round(ratio * 90)))
                        }
                        onPositionChanged: {
                            if (!pressed) return
                            var ratio = (mouseX / width - 0.5) * 2
                            aimRoot.aimAngle = Math.max(-90, Math.min(90, Math.round(ratio * 90)))
                        }
                    }
                }
            }

            // Power row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "> POWER: " + ("000" + Math.round(aimRoot.aimPower)).slice(-3)
                    color: aimRoot.colAccent
                    font.pixelSize: 12
                    font.family: "monospace"
                    Layout.preferredWidth: 130
                }

                Item {
                    id: powerTrack
                    Layout.fillWidth:       true
                    Layout.preferredHeight: 16
                    opacity: aimRoot.controlsEnabled ? 1.0 : 0.35

                    Rectangle { anchors.fill: parent; color: "#1a1a1a"; radius: 2 }
                    Rectangle {
                        width: (aimRoot.aimPower / 100) * powerTrack.width
                        height: parent.height
                        color: aimRoot.colAccent
                        radius: 2
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: aimRoot.controlsEnabled
                        onPressed:        aimRoot.aimPower = Math.round(mouseX / width * 100)
                        onPositionChanged: if (pressed) aimRoot.aimPower = Math.max(0, Math.min(100, Math.round(mouseX / width * 100)))
                    }
                }
            }

            // Fire button
            Rectangle {
                Layout.fillWidth:       true
                Layout.preferredHeight: 30
                radius: 3
                color: fireArea.containsMouse && aimRoot.controlsEnabled ? aimRoot.colHover : aimRoot.colBase
                border.color: aimRoot.controlsEnabled ? aimRoot.colAccent : aimRoot.colMuted
                opacity: aimRoot.controlsEnabled ? 1.0 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: "[ FIRE ]"
                    color: aimRoot.controlsEnabled ? aimRoot.colAccent : aimRoot.colMuted
                    font.pixelSize: 13
                    font.family: "monospace"
                    font.bold: true
                }

                MouseArea {
                    id: fireArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: aimRoot.controlsEnabled
                    onClicked: aimRoot.fireClicked()
                }
            }
        }
    }
}
