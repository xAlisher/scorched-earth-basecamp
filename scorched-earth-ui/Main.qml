import QtQuick 2.15
import QtQuick.Layouts 1.15

// Hot-seat game loop orchestrator.
// Layout: GameCanvas (960×480) + AimControl (100) + RoomPanel (100) = 680px total.
Rectangle {
    id: root
    width:  960
    height: 680
    color:  "#0d0d0d"
    focus:  true

    // ── palette ──────────────────────────────────────────────────────────────
    readonly property string colBg:      "#0d0d0d"
    readonly property string colSurface: "#111111"
    readonly property string colBorder:  "#1a1a1a"
    readonly property string colTerrain: "#1a3a1a"
    readonly property string colEdge:    "#00ff41"
    readonly property string colP1:      "#ffdd00"
    readonly property string colP2:      "#ff4444"
    readonly property string colProj:    "#ffff00"
    readonly property string colGhost:   "#2a2a4a"
    readonly property string colText:    "#c0c0c0"
    readonly property string colAccent:  "#00ff41"
    readonly property string colMuted:   "#444444"
    readonly property string colDanger:  "#ff4444"

    // ── state ────────────────────────────────────────────────────────────────
    property int    activePlayer:  1
    property int    gamePhase:     0      // 0=init 1=aim 2=anim 3=gameover
    property var    terrain:       []
    property var    tanks:         []
    property int    turnSeq:       0
    property int    gameStatus:    0      // 0=ongoing 1=p1wins 2=p2wins

    // ── turn log ─────────────────────────────────────────────────────────────
    property var    turnLog:       []    // [{turn, player, angle, power, result}]
    property var    lastShot:      null  // carries shot info from onFire to onAnimationComplete

    property int    myRole:        0      // 0=hotseat 1=P1-net 2=P2-net
    property bool   multiplayerOn: false
    property bool   pollBusy:      false
    property string ownPubKey:     ""

    property var    trajectoryPts: []
    property var    ghostArcPts:   []
    property int    animFrame:     0
    property var    projectile:    null

    property real   aimAngle:      0.0
    property real   aimPower:      50.0

    // per-player aim state — persists across turns, reset only on newGame
    property var    playerAim:     [{angle: 0, power: 50}, {angle: 0, power: 50}]

    // hotseat: myTurn is true whenever it's the aiming phase
    readonly property bool myTurn: root.gamePhase === 1

    // ── helpers ──────────────────────────────────────────────────────────────
    function callModuleParse(raw) {
        try {
            var tmp = JSON.parse(raw)
            if (typeof tmp === 'string') {
                try { return JSON.parse(tmp) } catch(e) { return tmp }
            }
            return tmp
        } catch(e) { return null }
    }

    function randomRoomId() {
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        var id = ""
        for (var i = 0; i < 6; i++)
            id += chars.charAt(Math.floor(Math.random() * chars.length))
        return id
    }

    function syncState(state) {
        if (!state) return
        if (state.terrain)      root.terrain      = state.terrain.slice()
        if (state.tanks)        root.tanks        = state.tanks.slice()
        if (state.activePlayer) root.activePlayer = state.activePlayer
        root.turnSeq    = state.turnSeq || 0
        root.gameStatus = state.status  || 0
    }

    // ── lifecycle ────────────────────────────────────────────────────────────
    Component.onCompleted: startTimer.start()

    Timer {
        id: startTimer
        interval: 1
        repeat:   false
        onTriggered: root.initGame()
    }

    function initGame() {
        // qmllint disable unqualified
        var raw   = logos.callModule("scorched_earth", "newGame", [20, 10, 0])
        // qmllint enable unqualified
        var state = root.callModuleParse(raw)
        if (!state) return

        root.terrain       = state.terrain      || []
        root.tanks         = state.tanks        || []
        root.activePlayer  = state.activePlayer || 1
        root.turnSeq       = state.turnSeq      || 0
        root.gameStatus    = 0
        root.ghostArcPts   = []
        root.trajectoryPts = []
        root.animFrame     = 0
        root.projectile    = null
        root.aimAngle      = 0
        root.aimPower      = 50
        root.playerAim     = [{angle: 0, power: 50}, {angle: 0, power: 50}]
        aimCtrl.aimAngle   = 0
        aimCtrl.aimPower   = 50
        root.gamePhase     = 1
    }

    // ── fire handler ─────────────────────────────────────────────────────────
    function onFire() {
        if (!root.myTurn || root.gamePhase !== 1) return
        var tankId  = root.activePlayer          // C++ is 1-indexed (1 or 2)
        var tankIdx = root.activePlayer - 1      // JS array index (0 or 1)
        if (tankIdx < 0 || tankIdx >= root.tanks.length) return
        var tank = root.tanks[tankIdx]

        // freeze previous arc as ghost
        root.ghostArcPts = root.trajectoryPts.slice()

        // user angle: -90..+90, center=0=straight up; physics angle: 90-user
        var physAngle = 90.0 - aimCtrl.aimAngle

        // compute new arc and start animation (inlined — .js import blocked in sandbox)
        var pts = []
        var rad = physAngle * Math.PI / 180.0
        var vx = Math.cos(rad) * aimCtrl.aimPower * 0.15
        var vy = -Math.sin(rad) * aimCtrl.aimPower * 0.15
        var px = tank.x + 24, py = tank.y   // fire from horizontal center of tank body
        var BS = 48, COLS = 20, ROWS = 10
        var startCol = Math.floor(px / BS)
        var startRow = Math.floor(py / BS)
        var leftStart = false
        while (px >= 0 && px < 960 && py < 480) {
            pts.push({ x: px, y: py })
            var tcol = Math.floor(px / BS)
            var trow = Math.floor(py / BS)
            if (!leftStart) {
                if (tcol !== startCol || trow !== startRow) leftStart = true
            }
            if (leftStart &&
                    tcol >= 0 && tcol < COLS && trow >= 0 && trow < ROWS &&
                    root.terrain[trow * COLS + tcol])
                break
            px += vx; py += vy; vy += 0.3
        }
        // processShot BEFORE gamePhase=2 — callModule blocks the JS thread;
        // if timer were already running it would fire re-entrantly inside the block
        // qmllint disable unqualified
        var shotRaw = logos.callModule("scorched_earth", "processShot",
            [tankId, physAngle, aimCtrl.aimPower])
        // qmllint enable unqualified
        var shotResult = root.callModuleParse(shotRaw)
        root.lastShot = {
            player: root.activePlayer,
            angle:  Math.round(aimCtrl.aimAngle),
            power:  Math.round(aimCtrl.aimPower),
            result: shotResult
        }
        root.trajectoryPts = pts
        root.animFrame = 0
        root.gamePhase = 2   // GameCanvas timer starts AFTER processShot returns
    }

    // ── animation-complete handler ────────────────────────────────────────────
    function onAnimationComplete() {
        root.gamePhase = 0   // stop timer BEFORE callModule — prevents re-entrant animationComplete
        root.ghostArcPts = root.trajectoryPts.slice()   // freeze arc as ghost
        root.projectile  = null

        // save current player's aim before syncState flips activePlayer
        var prevIdx = root.activePlayer - 1
        var saved   = root.playerAim.slice()
        saved[prevIdx] = { angle: aimCtrl.aimAngle, power: aimCtrl.aimPower }
        root.playerAim = saved

        // refresh full state from C++ (terrain + hp + activePlayer all updated)
        // qmllint disable unqualified
        var raw   = logos.callModule("scorched_earth", "getState", [])
        // qmllint enable unqualified
        var state = root.callModuleParse(raw)
        root.syncState(state)

        // restore next player's aim
        var nextIdx = root.activePlayer - 1
        aimCtrl.aimAngle = root.playerAim[nextIdx].angle
        aimCtrl.aimPower = root.playerAim[nextIdx].power

        // build turn log entry
        if (root.lastShot) {
            var s    = root.lastShot
            var res  = s.result
            var outcome = "miss"
            if (res) {
                if (res.hit && res.tankId >= 0)
                    outcome = "HIT P" + res.tankId
                else if (res.hit && res.removedBlocks && res.removedBlocks.length > 0)
                    outcome = "blk[" + res.removedBlocks[0][0] + "," + res.removedBlocks[0][1] + "]"
            }
            var entry = {
                turn:    root.turnSeq,
                player:  s.player,
                angle:   s.angle,
                power:   s.power,
                outcome: outcome
            }
            var log = [entry].concat(root.turnLog).slice(0, 8)
            root.turnLog = log
            root.lastShot = null
        }

        root.gamePhase = (root.gameStatus !== 0) ? 3 : 1
    }

    // ── keyboard ─────────────────────────────────────────────────────────────
    Keys.onPressed: function(event) {
        if (event.isAutoRepeat)        { event.accepted = true;  return }
        if (root.gamePhase !== 1)      { event.accepted = false; return }
        if (event.key === Qt.Key_Space) { root.onFire(); event.accepted = true; return }
        var dir = 0
        if (event.key === Qt.Key_Left)  dir = -1
        if (event.key === Qt.Key_Right) dir =  1
        if (dir === 0) { event.accepted = false; return }

        var tankIdx = root.activePlayer   // C++ moveTank is 1-indexed
        // qmllint disable unqualified
        logos.callModule("scorched_earth", "moveTank", [tankIdx, dir])
        var raw = logos.callModule("scorched_earth", "getState", [])
        // qmllint enable unqualified
        var state = root.callModuleParse(raw)
        if (state) {
            if (state.tanks) root.tanks = state.tanks
            if (state.terrain) {
                // terrain array requires slice+reassign — NOT in-place mutation
                root.terrain = state.terrain.slice()
            }
        }
        event.accepted = true
    }

    // ── layout ───────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        GameCanvas {
            id: gameCanvas
            Layout.fillWidth:       true
            Layout.preferredHeight: 480
            terrain:       root.terrain
            tanks:         root.tanks
            ghostArcPts:   root.ghostArcPts
            trajectoryPts: root.trajectoryPts
            gameStatus:    root.gameStatus
            activePlayer:  root.activePlayer
            gamePhase:     root.gamePhase
            onAnimationComplete: root.onAnimationComplete()
            onTerrainChanged: requestPaint()
        }

        AimControl {
            id: aimCtrl
            Layout.fillWidth:  true
            myTurn:       root.myTurn
            gamePhase:    root.gamePhase
            activePlayer: root.activePlayer
            onAimAngleChanged: root.aimAngle = aimAngle
            onAimPowerChanged: root.aimPower = aimPower
            onFireClicked:     root.onFire()
        }

        RoomPanel {
            Layout.fillWidth: true
            turnLog: root.turnLog
        }
    }

    // ── game over overlay ─────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color:   "#cc000000"
        visible: root.gamePhase === 3
        z: 1

        Column {
            anchors.centerIn: parent
            spacing: 24

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:  root.gameStatus === 1 ? ">> P1 WINS <<" : ">> P2 WINS <<"
                color: root.gameStatus === 1 ? root.colP1 : root.colP2
                font.pixelSize: 36
                font.family:    "monospace"
                font.bold:      true
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width:  200
                height: 40
                radius: 3
                color:        newGameArea.containsMouse ? "#1a3a1a" : "#0e2218"
                border.color: root.colAccent

                Text {
                    anchors.centerIn: parent
                    text:           "[ NEW GAME ]"
                    color:          root.colAccent
                    font.pixelSize: 14
                    font.family:    "monospace"
                    font.bold:      true
                }

                MouseArea {
                    id: newGameArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked:    root.initGame()
                }
            }
        }
    }
}
