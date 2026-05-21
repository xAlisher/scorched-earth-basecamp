import QtQuick 2.15
import QtQuick.Layouts 1.15

// Game orchestrator.
// Layout: GameCanvas (960×480) + AimControl (100) + RoomPanel (100) = 680px total.
// uiPhase: "modePicker" → "p2pSetup" → "playing"  (or modePicker → playing for hotseat)
Rectangle {
    id: root
    width:  960
    height: 680
    color:  "#0d0d0d"
    focus:  true

    // Register scorched_earth events at load time.
    Component.onCompleted: {
        // qmllint disable unqualified
        if (typeof logos !== "undefined") {
            logos.onModuleEvent("scorched_earth", "p2pMessage")
            logos.onModuleEvent("scorched_earth", "p2pStatus")
        }
        // qmllint enable unqualified
    }

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

    // ── game state ───────────────────────────────────────────────────────────
    property int    activePlayer:  1
    property int    gamePhase:     0      // 0=init 1=aim 2=anim 3=gameover
    property var    terrain:       []
    property var    tanks:         []
    property int    turnSeq:       0
    property int    gameStatus:    0      // 0=ongoing 1=p1wins 2=p2wins

    // ── turn log ─────────────────────────────────────────────────────────────
    property var    turnLog:       []    // [{turn, player, angle, power, outcome}]
    property var    lastShot:      null  // shot info from applyShot to onAnimationComplete

    // ── P2P state ────────────────────────────────────────────────────────────
    property int    myRole:        0      // 0=hotseat 1=P1(creator) 2=P2(joiner)
    property bool   multiplayerOn: false
    property string contentTopic:  ""
    property string roomId:        ""
    property bool   peerConnected: false
    property int    netSeq:        0
    property string myPeerId:     Math.random().toString(36).substr(2, 9)
    property var    sentSeqs:      ({})   // seq->true, self-echo filter
    property string nodeStatus:   ""     // Waku connection state from p2pStatus event

    // ── UI phase ─────────────────────────────────────────────────────────────
    property string uiPhase:      "modePicker"  // "modePicker"|"p2pSetup"|"playing"
    property string p2pPhase:     ""            // ""|"creating"|"joining"

    // ── animation state ──────────────────────────────────────────────────────
    property var    trajectoryPts: []
    property var    ghostArcPts:   []
    property int    animFrame:     0
    property var    projectile:    null

    property real   aimAngle:      0.0
    property real   aimPower:      50.0
    property var    playerAim:     [{angle: 0, power: 50}, {angle: 0, power: 50}]

    // myTurn: hotseat=always during aim; P2P=only on your role's turn
    readonly property bool myTurn: gamePhase === 1 && (myRole === 0 || activePlayer === myRole)

    // pending P2P message payloads (deferred to avoid callModule inside event cb)
    property var _pendingShot:    null
    property var _pendingStart:   null
    property var _outgoingShot:   null   // shot to send after animation completes

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
        if (state.terrain)                  root.terrain      = state.terrain.slice()
        if (state.tanks)                    root.tanks        = state.tanks.slice()
        if (state.activePlayer !== undefined) root.activePlayer = state.activePlayer
        root.turnSeq    = state.turnSeq || 0
        root.gameStatus = state.status  || 0
    }

    function sendMsg(obj) {
        root.netSeq += 1
        obj.seq = root.netSeq
        obj.pid = root.myPeerId
        root.sentSeqs[obj.seq] = true
        // qmllint disable unqualified
        logos.callModule("scorched_earth", "sendP2PMsg", [JSON.stringify(obj)])
        // qmllint enable unqualified
    }

    // ── P2P init timer ────────────────────────────────────────────────────────
    Timer {
        id: p2pInitTimer
        repeat:   false
        interval: 1
        onTriggered: {
            console.log("[SE-P2P] init topic=" + root.contentTopic)
            root.nodeStatus = "Connecting..."
            // qmllint disable unqualified
            logos.callModule("scorched_earth", "enableMultiplayer", [root.contentTopic])
            logos.onModuleEvent("scorched_earth", "p2pMessage")
            logos.onModuleEvent("scorched_earth", "p2pStatus")
            // qmllint enable unqualified
            root.multiplayerOn = true
            // joinRetryTimer starts from p2pStatus "Connected" handler (GUEST)
            // or from joinHandlerTimer (HOST) after peer joins
        }
    }

    // Deferred: apply a received shot (avoids logos.callModule inside event cb)
    Timer {
        id: shotApplyTimer
        repeat:     false
        interval:   100
        onTriggered: {
            if (!root._pendingShot) return
            if (root.gamePhase !== 1) { shotApplyTimer.start(); return }  // still animating, retry
            var m = root._pendingShot
            root._pendingShot = null
            root.applyReceivedShot(m.i, m.pa, m.pw, m.ua, m.pp, m.result)
        }
    }

    // Deferred: Creator received "join" → start game and broadcast state
    Timer {
        id: joinHandlerTimer
        repeat:     false
        interval:   1
        onTriggered: {
            joinRetryTimer.stop()    // stop any pending retries on both sides
            root.peerConnected = true
            root.uiPhase = "playing"
            root.initGame()
            root.sendMsg({ t: "start", state: {
                terrain:      root.terrain.slice(),
                tanks:        root.tanks.slice(),
                activePlayer: root.activePlayer,
                turnSeq:      root.turnSeq
            }})
        }
    }

    // Deferred: Joiner received "start" → apply state and enter game
    Timer {
        id: startHandlerTimer
        repeat:     false
        interval:   1
        onTriggered: {
            if (root._pendingStart && !root.peerConnected) {
                var s = root._pendingStart
                root._pendingStart = null
                joinRetryTimer.stop()
                root.peerConnected = true
                // Initialize GUEST's C++ state from received snapshot
                // qmllint disable unqualified
                logos.callModule("scorched_earth", "loadState", [JSON.stringify(s.state)])
                // qmllint enable unqualified
                root.syncState(s.state)
                root.uiPhase       = "playing"
                root.ghostArcPts   = []
                root.trajectoryPts = []
                root.animFrame     = 0
                root.projectile    = null
                root.turnLog       = []
                root.playerAim     = [{angle: 0, power: 50}, {angle: 0, power: 50}]
                aimCtrl.aimAngle   = 0
                aimCtrl.aimPower   = 50
                root.gamePhase     = 1
            }
        }
    }

    // ── join retry timer (guest resends join every 500ms until peer responds) ────
    Timer {
        id: joinRetryTimer
        repeat:   true
        interval: 500
        onTriggered: {
            if (root.multiplayerOn && root.p2pPhase === "joining" && !root.peerConnected) {
                console.log("[SE-P2P] join retry")
                root.sendMsg({ t: "join" })
            } else {
                joinRetryTimer.stop()
            }
        }
    }

    // ── deferred re-send of start to late-joining guest (avoids callModule inside event cb) ─
    Timer {
        id: resendStartTimer
        repeat:   false
        interval: 1
        onTriggered: {
            // Only resend while peer hasn't connected yet — stops the flood of
            // resend-starts once GUEST is already in game.
            if (root.myRole === 1 && root.uiPhase === "playing" && !root.peerConnected) {
                // qmllint disable unqualified
                root.sendMsg({ t: "start", state: {
                    terrain:      root.terrain.slice(),
                    tanks:        root.tanks.slice(),
                    activePlayer: root.activePlayer,
                    turnSeq:      root.turnSeq
                }})
                // qmllint enable unqualified
            }
        }
    }


    // ── scorched_earth p2p event receiver ─────────────────────────────────────
    // scorched_earth C++ core forwards delivery_module messages as "p2pMessage"
    // with data[0] = base64(JSON payload).
    Connections {
        target: typeof logos !== "undefined" ? logos : null
        function onModuleEventReceived(moduleName, eventName, data) {
            console.log("[SE-P2P] event mod=" + moduleName + " ev=" + eventName)
            if (moduleName !== "scorched_earth") return
            if (eventName === "p2pStatus") {
                console.log("[SE-P2P] p2pStatus raw data=" + JSON.stringify(data) + " data[0]=" + data[0] + " typeof=" + typeof data)
                var s = (data && data[0]) ? data[0] : (typeof data === "string" ? data : "")
                root.nodeStatus = s
                console.log("[SE-P2P] nodeStatus=" + root.nodeStatus)
                // Only trigger join on the normalized "Connected" emitted by C++ after
                // connectionStateChanged fires — not on intermediate "Connecting..." strings.
                var isConnected = s === "Connected"
                if (isConnected && root.p2pPhase === "joining" && !root.peerConnected) {
                    // Do NOT call sendMsg here — logos.callModule inside an event handler
                    // causes QML thread reentrancy that breaks subsequent event delivery.
                    // Let joinRetryTimer fire and send the first join outside the handler.
                    joinRetryTimer.start()
                }
                return
            }
            if (eventName !== "p2pMessage") return
            try {
                console.log("[SE-P2P] data[0]=" + (data ? data[0] : "null"))
                var raw = data[0]
                var msgStr = raw
                try { msgStr = Qt.atob(raw) } catch(e) {}
                var msg = JSON.parse(msgStr)
                console.log("[SE-P2P] msg.t=" + msg.t + " seq=" + msg.seq + " pid=" + msg.pid + " myPid=" + root.myPeerId)
                if (root.sentSeqs[msg.seq] && msg.pid === root.myPeerId) {
                    console.log("[SE-P2P] self-echo drop seq=" + msg.seq)
                    return
                }
                if (msg.t === "s") {
                    // Dedup: drop if gameTurnSeq was already applied
                    if (msg.gts !== undefined && msg.gts < root.turnSeq) {
                        console.log("[SE-P2P] dup shot drop gts=" + msg.gts + " myTurnSeq=" + root.turnSeq)
                        return
                    }
                    root._pendingShot = msg
                    shotApplyTimer.start()
                } else if (msg.t === "join") {
                    if (root.myRole === 1) {
                        // Re-send start even if already playing (handles guest retry).
                        // Use deferred timers — never call sendMsg inside an event handler
                        // (logos.callModule reentrancy breaks p2pMessage event delivery).
                        if (root.uiPhase === "playing") {
                            resendStartTimer.start()
                        } else {
                            joinHandlerTimer.start()
                        }
                    }
                } else if (msg.t === "start") {
                    // Joiner: received game state → enter game
                    root._pendingStart = msg
                    startHandlerTimer.start()
                }
            } catch(e) {
                console.log("[SE-P2P] event parse error: " + e)
            }
        }
    }

    function enableMultiplayer(topic) {
        if (root.multiplayerOn) return   // guard — C++ mpEnabled_ handles double-init
        root.contentTopic = topic
        p2pInitTimer.start()
    }

    // ── game init ────────────────────────────────────────────────────────────
    // Not called on Component.onCompleted — mode picker shows first.
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
        root.turnLog       = []
        root.gamePhase     = 1
    }

    // ── shot execution ────────────────────────────────────────────────────────
    // Local shot: computes QML arc + calls processShot C++.
    function applyShot(tankId, physAngle, power, userAngle) {
        var tankIdx = tankId - 1
        if (tankIdx < 0 || tankIdx >= root.tanks.length) return
        var tank = root.tanks[tankIdx]

        root.ghostArcPts = root.trajectoryPts.slice()

        var pts = []
        var rad = physAngle * Math.PI / 180.0
        var vx = Math.cos(rad) * power * 0.15
        var vy = -Math.sin(rad) * power * 0.15
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
        // processShot BEFORE gamePhase=2 — blocks the JS thread; must not be inside
        // a running Timer (reentrancy).  Called here before setting gamePhase=2.
        // qmllint disable unqualified
        var shotRaw = logos.callModule("scorched_earth", "processShot",
            [tankId, physAngle, power])
        // qmllint enable unqualified
        var shotResult = root.callModuleParse(shotRaw)
        root.lastShot = {
            player: tankId,
            angle:  Math.round(userAngle),
            power:  Math.round(power),
            result: shotResult
        }
        root.trajectoryPts = pts
        root.animFrame     = 0
        root.gamePhase     = 2   // GameCanvas timer starts AFTER processShot returns
    }

    // Received shot: animate using peer's physics params; apply bundled result in onAnimationComplete.
    // No processShot / loadState IPC calls — no blocking.
    function applyReceivedShot(tankId, physAngle, power, userAngle, prePos, result) {
        var tankIdx = tankId - 1
        if (tankIdx < 0 || tankIdx >= root.tanks.length) return

        // 1. Apply shooter's position FIRST — correct starting point for trajectory
        if (prePos) {
            var pt = root.tanks.slice()
            pt[tankIdx] = Object.assign({}, pt[tankIdx], { x: prePos.x, y: prePos.y })
            root.tanks = pt
        }

        var tank = root.tanks[tankIdx]
        root.ghostArcPts = root.trajectoryPts.slice()

        var pts = []
        var rad = physAngle * Math.PI / 180.0
        var vx = Math.cos(rad) * power * 0.15
        var vy = -Math.sin(rad) * power * 0.15
        var px = tank.x + 24, py = tank.y
        var BS = 48, COLS = 20, ROWS = 10
        var startCol = Math.floor(px / BS)
        var startRow = Math.floor(py / BS)
        var leftStart = false
        while (px >= 0 && px < 960 && py < 480) {
            pts.push({ x: px, y: py })
            var tcol = Math.floor(px / BS)
            var trow = Math.floor(py / BS)
            if (!leftStart) { if (tcol !== startCol || trow !== startRow) leftStart = true }
            if (leftStart && tcol >= 0 && tcol < COLS && trow >= 0 && trow < ROWS && root.terrain[trow * COLS + tcol])
                break
            px += vx; py += vy; vy += 0.3
        }
        root.lastShot = { player: tankId, angle: Math.round(userAngle), power: Math.round(power),
                          result: result, _received: true }
        root.trajectoryPts = pts
        root.animFrame     = 0
        root.gamePhase     = 2
    }

    // ── fire handler ─────────────────────────────────────────────────────────
    function onFire() {
        if (!root.myTurn || root.gamePhase !== 1) return
        var tankId    = root.activePlayer
        var physAngle = 90.0 - aimCtrl.aimAngle
        var power     = aimCtrl.aimPower
        var userAngle = aimCtrl.aimAngle
        if (root.multiplayerOn) {
            var me = root.tanks[tankId - 1]
            root._outgoingShot = { t: "s", i: tankId, pa: physAngle,
                                   pw: power, ua: userAngle,
                                   gts: root.turnSeq,
                                   pp: { x: me.x, y: me.y } }
        }
        applyShot(tankId, physAngle, power, userAngle)
    }

    // ── animation-complete handler ────────────────────────────────────────────
    function onAnimationComplete() {
        root.gamePhase = 0   // stop timer BEFORE callModule — prevents re-entrant animationComplete
        root.ghostArcPts = root.trajectoryPts.slice()
        root.projectile  = null

        // save current player's aim before syncState flips activePlayer
        var prevIdx = root.activePlayer - 1
        var saved   = root.playerAim.slice()
        saved[prevIdx] = { angle: aimCtrl.aimAngle, power: aimCtrl.aimPower }
        root.playerAim = saved

        var shotPayloadResult = null

        if (root.lastShot && root.lastShot._received) {
            // ── GUEST: apply bundled result — no IPC before this point ──
            var rr = root.lastShot.result
            if (rr) {
                var terrainChanged = rr.bc >= 0 && rr.br >= 0
                // 1. Remove destroyed block
                if (terrainChanged) {
                    var newT = root.terrain.slice()
                    newT[rr.br * 20 + rr.bc] = false
                    root.terrain = newT
                }
                // 2. HP only — keep each player's own x/y (prePos handled position)
                var myIdx = root.myRole - 1
                var ut = root.tanks.slice()
                if (rr.hp) {
                    ut[0] = Object.assign({}, ut[0], { hp: rr.hp[0] })
                    ut[1] = Object.assign({}, ut[1], { hp: rr.hp[1] })
                }
                // 3. If my floor was destroyed, recalculate my y
                if (terrainChanged) {
                    var myCol = Math.floor(ut[myIdx].x / 48)
                    if (myCol === rr.bc && Math.floor(ut[myIdx].y / 48) === rr.br) {
                        var sr = rr.br + 1
                        while (sr < 10 && !root.terrain[sr * 20 + myCol]) sr++
                        ut[myIdx] = Object.assign({}, ut[myIdx], sr < 10 ? { y: sr * 48 } : { hp: 0 })
                    }
                }
                root.tanks = ut
                if (rr.ap !== undefined) root.activePlayer = rr.ap
                root.turnSeq    = rr.ts !== undefined ? rr.ts : root.turnSeq
                root.gameStatus = rr.st !== undefined ? rr.st : root.gameStatus
                // 4. Sync C++ only if terrain changed (needed for moveTank collision)
                if (terrainChanged) {
                    // qmllint disable unqualified
                    logos.callModule("scorched_earth", "loadState", [JSON.stringify({
                        terrain: root.terrain, tanks: root.tanks,
                        activePlayer: root.activePlayer, turnSeq: root.turnSeq, status: root.gameStatus
                    })])
                    // qmllint enable unqualified
                }
            }
        } else {
            // ── HOST (local shot): authoritative state from C++ ──
            // qmllint disable unqualified
            var raw   = logos.callModule("scorched_earth", "getState", [])
            // qmllint enable unqualified
            var state = root.callModuleParse(raw)
            root.syncState(state)

            // Build result to bundle into outgoing shot message
            if (root.multiplayerOn && root._outgoingShot && root.lastShot) {
                var res = root.lastShot.result
                var bc = (res && res.removedBlocks && res.removedBlocks.length > 0) ? res.removedBlocks[0][0] : -1
                var br = (res && res.removedBlocks && res.removedBlocks.length > 0) ? res.removedBlocks[0][1] : -1
                shotPayloadResult = { bc: bc, br: br,
                                      th: res ? res.tankId : -1,
                                      hp: [root.tanks[0].hp, root.tanks[1].hp],
                                      ap: root.activePlayer,
                                      ts: root.turnSeq,
                                      st: root.gameStatus }
            }
        }

        // restore next player's aim
        var nextIdx = root.activePlayer - 1
        aimCtrl.aimAngle = root.playerAim[nextIdx].angle
        aimCtrl.aimPower = root.playerAim[nextIdx].power

        // build turn log entry
        if (root.lastShot) {
            var sl      = root.lastShot
            var rl      = sl.result
            var outcome = "miss"
            if (rl) {
                // received shot (short format): th/bc/br
                if (rl.th >= 0)                               outcome = "HIT P" + rl.th
                else if (rl.bc >= 0)                          outcome = "blk[" + rl.bc + "," + rl.br + "]"
                // local shot (processShot format): hit/tankId/removedBlocks
                else if (rl.hit && rl.tankId >= 0)            outcome = "HIT P" + rl.tankId
                else if (rl.hit && rl.removedBlocks && rl.removedBlocks.length > 0)
                    outcome = "blk[" + rl.removedBlocks[0][0] + "," + rl.removedBlocks[0][1] + "]"
            }
            root.turnLog = [{ turn: root.turnSeq, player: sl.player, angle: sl.angle, power: sl.power, outcome: outcome }]
                           .concat(root.turnLog).slice(0, 8)
            root.lastShot = null
        }

        root.gamePhase = (root.gameStatus !== 0) ? 3 : 1

        // Send shot to peer after animation (HOST only — result bundled, no preState)
        if (root.multiplayerOn && root._outgoingShot) {
            var pending = root._outgoingShot
            root._outgoingShot = null
            pending.result = shotPayloadResult
            root.sendMsg(pending)
        }
    }

    // ── keyboard ─────────────────────────────────────────────────────────────
    Keys.onPressed: function(event) {
        if (event.isAutoRepeat)        { event.accepted = true;  return }
        if (root.gamePhase !== 1)      { event.accepted = false; return }
        if (!root.myTurn)              { event.accepted = false; return }
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
            if (state.tanks)   root.tanks   = state.tanks
            if (state.terrain) root.terrain = state.terrain.slice()
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
            turnLog:       root.turnLog
            multiplayerOn: root.multiplayerOn
            roomId:        root.roomId
            peerConnected: root.peerConnected
            myRole:        root.myRole
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
                    onClicked: {
                        root.initGame()
                        // In P2P: creator broadcasts new state; peer applies it
                        if (root.multiplayerOn && root.myRole === 1) {
                            root.sendMsg({ t: "start", state: {
                                terrain:      root.terrain.slice(),
                                tanks:        root.tanks.slice(),
                                activePlayer: root.activePlayer,
                                turnSeq:      root.turnSeq
                            }})
                        }
                    }
                }
            }
        }
    }

    // ── clipboard helper (must be root-level child — nested copy() is silent) ──
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    function copyToClipboard(txt) {
        clipboardHelper.text = txt
        clipboardHelper.selectAll()
        clipboardHelper.copy()
    }

    // ── mode picker overlay ───────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color:   "#e6000000"
        visible: root.uiPhase === "modePicker"
        z: 10

        Column {
            anchors.centerIn: parent
            spacing: 32

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:  "SCORCHED EARTH"
                color: root.colAccent
                font.pixelSize: 28
                font.family:    "monospace"
                font.bold:      true
                font.letterSpacing: 4
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width:  200
                    height: 44
                    radius: 3
                    color:        hotSeatArea.containsMouse ? "#1a3a1a" : "#0e2218"
                    border.color: root.colAccent

                    Text {
                        anchors.centerIn: parent
                        text:           "[ HOT SEAT ]"
                        color:          root.colAccent
                        font.pixelSize: 15
                        font.family:    "monospace"
                        font.bold:      true
                    }

                    MouseArea {
                        id: hotSeatArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.myRole  = 0
                            root.uiPhase = "playing"
                            root.initGame()
                        }
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width:  200
                    height: 44
                    radius: 3
                    color:        p2pPickArea.containsMouse ? "#2a1a00" : "#1a0e00"
                    border.color: root.colP1

                    Text {
                        anchors.centerIn: parent
                        text:           "[ P2P ]"
                        color:          root.colP1
                        font.pixelSize: 15
                        font.family:    "monospace"
                        font.bold:      true
                    }

                    MouseArea {
                        id: p2pPickArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.uiPhase  = "p2pSetup"
                            root.p2pPhase = ""
                        }
                    }
                }
            }
        }
    }

    // ── P2P setup overlay ─────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color:   "#e6000000"
        visible: root.uiPhase === "p2pSetup"
        z: 10

        Column {
            anchors.centerIn: parent
            spacing: 20
            width: 320

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:  "P2P MATCH"
                color: root.colP1
                font.pixelSize: 22
                font.family:    "monospace"
                font.bold:      true
                font.letterSpacing: 3
            }

            // ── CREATE / JOIN choice ──────────────────────────────────────────
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16
                visible: root.p2pPhase === ""

                Rectangle {
                    width:  140
                    height: 40
                    radius: 3
                    color:        createArea.containsMouse ? "#1a3a1a" : "#0e2218"
                    border.color: root.colAccent

                    Text {
                        anchors.centerIn: parent
                        text:  "[ CREATE ]"
                        color: root.colAccent
                        font.pixelSize: 13
                        font.family:    "monospace"
                        font.bold:      true
                    }

                    MouseArea {
                        id: createArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.myRole   = 1
                            root.roomId   = root.randomRoomId()
                            root.p2pPhase = "creating"
                            console.log("[SE-P2P] CREATE clicked, roomId=" + root.roomId)
                            root.enableMultiplayer(
                                "/scorched-earth/1/room-" + root.roomId + "/json")
                        }
                    }
                }

                Rectangle {
                    width:  140
                    height: 40
                    radius: 3
                    color:        joinArea.containsMouse ? "#2a1a1a" : "#1a0e0e"
                    border.color: root.colP2

                    Text {
                        anchors.centerIn: parent
                        text:  "[ JOIN ]"
                        color: root.colP2
                        font.pixelSize: 13
                        font.family:    "monospace"
                        font.bold:      true
                    }

                    MouseArea {
                        id: joinArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.myRole   = 2
                            root.p2pPhase = "joining"
                        }
                    }
                }
            }

            // ── CREATE sub-panel: show room code, wait for peer ───────────────
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                visible: root.p2pPhase === "creating"

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:  "SHARE THIS CODE WITH YOUR OPPONENT"
                    color: root.colMuted
                    font.pixelSize: 10
                    font.family:    "monospace"
                    font.letterSpacing: 1
                }

                TextEdit {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:          root.roomId
                    color:         root.colAccent
                    font.pixelSize: 40
                    font.family:    "monospace"
                    font.bold:      true
                    font.letterSpacing: 8
                    readOnly:       true
                    selectByMouse:  true
                    selectedTextColor:   "#000000"
                    selectionColor:      root.colAccent
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width:  100
                    height: 28
                    radius: 3
                    color:        copyArea.containsMouse ? "#1a3a1a" : "#0e2218"
                    border.color: root.colAccent

                    Text {
                        id: copyLabel
                        anchors.centerIn: parent
                        text:  "[ COPY ]"
                        color: root.colAccent
                        font.pixelSize: 11
                        font.family:    "monospace"
                        font.bold:      true
                    }

                    MouseArea {
                        id: copyArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.copyToClipboard(root.roomId)
                            copyLabel.text = "COPIED!"
                            copyResetTimer.start()
                        }
                    }

                    Timer {
                        id: copyResetTimer
                        interval: 1500
                        repeat:   false
                        onTriggered: copyLabel.text = "[ COPY ]"
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:  root.peerConnected ? "PEER CONNECTED — STARTING..." : "WAITING FOR PEER..."
                    color: root.peerConnected ? root.colAccent : root.colMuted
                    font.pixelSize: 12
                    font.family:    "monospace"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.nodeStatus !== ""
                    text:  "NODE: " + root.nodeStatus
                    color: root.nodeStatus.toLowerCase().indexOf("connect") >= 0 &&
                           root.nodeStatus.toLowerCase().indexOf("disconnect") < 0
                           ? root.colAccent : root.colMuted
                    font.pixelSize: 10
                    font.family:    "monospace"
                }
            }

            // ── JOIN sub-panel: enter code + connect ──────────────────────────
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                visible: root.p2pPhase === "joining"

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:  "ENTER ROOM CODE"
                    color: root.colMuted
                    font.pixelSize: 10
                    font.family:    "monospace"
                    font.letterSpacing: 2
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width:  220
                    height: 48
                    color:  "#111111"
                    border.color: codeInput.activeFocus ? root.colP2 : root.colBorder
                    radius: 3

                    TextInput {
                        id: codeInput
                        anchors.centerIn: parent
                        width: parent.width - 20
                        color: root.colP2
                        font.pixelSize:   22
                        font.family:      "monospace"
                        font.bold:        true
                        font.letterSpacing: 5
                        maximumLength:    6
                        cursorVisible:    activeFocus
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:  root.multiplayerOn ? "CONNECTING..." : " "
                    color: root.colMuted
                    font.pixelSize: 11
                    font.family:    "monospace"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.nodeStatus !== "" && root.multiplayerOn
                    text:  "NODE: " + root.nodeStatus
                    color: root.nodeStatus.toLowerCase().indexOf("connect") >= 0 &&
                           root.nodeStatus.toLowerCase().indexOf("disconnect") < 0
                           ? root.colAccent : root.colMuted
                    font.pixelSize: 10
                    font.family:    "monospace"
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width:  140
                    height: 36
                    radius: 3
                    opacity: (codeInput.text.length === 6 && !root.multiplayerOn) ? 1.0 : 0.4
                    color:        connectArea.containsMouse ? "#2a1a1a" : "#1a0e0e"
                    border.color: root.colP2

                    Text {
                        anchors.centerIn: parent
                        text:  "[ CONNECT ]"
                        color: root.colP2
                        font.pixelSize: 13
                        font.family:    "monospace"
                        font.bold:      true
                    }

                    MouseArea {
                        id: connectArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (codeInput.text.length !== 6 || root.multiplayerOn) return
                            root.roomId = codeInput.text.toUpperCase()
                            root.enableMultiplayer(
                                "/scorched-earth/1/room-" + root.roomId + "/json")
                        }
                    }
                }
            }

            // ── back button (only before delivery_module is initialized) ──────
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width:   100
                height:  30
                radius:  3
                visible: !root.multiplayerOn
                color:        backArea.containsMouse ? "#1a1a1a" : "#111111"
                border.color: root.colMuted

                Text {
                    anchors.centerIn: parent
                    text:  "< BACK"
                    color: root.colMuted
                    font.pixelSize: 11
                    font.family:    "monospace"
                }

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.uiPhase  = "modePicker"
                        root.p2pPhase = ""
                        root.roomId   = ""
                        root.myRole   = 0
                        codeInput.text = ""
                    }
                }
            }
        }
    }
}
