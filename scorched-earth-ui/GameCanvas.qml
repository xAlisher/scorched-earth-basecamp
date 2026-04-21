import QtQuick 2.15

// Canvas 960×480. Terminal aesthetic.
// Receives all state as properties; owns the projectile animation timer.
Canvas {
    id: canvas
    width:  960
    height: 480

    // ── state inputs ────────────────────────────────────────────────────────
    property var terrain:      []     // flat 0/1 array, cols*rows
    property var _terrain:     []     // explicit snapshot updated in onTerrainChanged
    property var tanks:        []     // [{x,y,hp}, ...]
    property var ghostArcPts:  []     // previous shot arc
    property var trajectoryPts:[]     // current shot arc (used during anim)
    property int gameStatus:   0      // 0=ongoing, 1=p1wins, 2=p2wins
    property int activePlayer: 1
    property int gamePhase:    0      // 0=init,1=aim,2=anim,3=gameover

    // ── animation ───────────────────────────────────────────────────────────
    property int _animFrame: 0
    signal animationComplete()

    Timer {
        id: animTimer
        interval: 16
        repeat: true
        running: canvas.gamePhase === 2
        onTriggered: {
            canvas._animFrame++
            if (canvas._animFrame >= canvas.trajectoryPts.length) {
                canvas._animFrame = 0
                canvas.animationComplete()
            }
            canvas.requestPaint()
        }
    }

    // repaint on any state change
    onTerrainChanged:       { _terrain = terrain.slice(); requestPaint() }
    onTanksChanged:         requestPaint()
    onGhostArcPtsChanged:   requestPaint()
    onTrajectoryPtsChanged: requestPaint()
    onGameStatusChanged:    requestPaint()
    onActivePlayerChanged:  requestPaint()
    onGamePhaseChanged:     requestPaint()

    // ── constants ────────────────────────────────────────────────────────────
    readonly property int bs: 48        // BLOCK_SIZE
    readonly property int cols: 20
    readonly property int rows: 10

    // ── palette ──────────────────────────────────────────────────────────────
    readonly property string colBg:          "#0d0d0d"
    readonly property string colTerrain:     "#1a3a1a"
    readonly property string colTerrainEdge: "#00ff41"
    readonly property string colP1:          "#ffdd00"
    readonly property string colP2:          "#ff4444"
    readonly property string colProjectile:  "#ffff00"
    readonly property string colGhostArc:    "#2a2a4a"
    readonly property string colText:        "#c0c0c0"

    // ── paint ─────────────────────────────────────────────────────────────────
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        // 1. Background
        ctx.fillStyle = colBg
        ctx.fillRect(0, 0, width, height)

        // 2. Ghost arc — previous shot, dim dotted
        if (ghostArcPts.length > 1) {
            ctx.save()
            ctx.setLineDash([4, 6])
            ctx.strokeStyle = colGhostArc
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(ghostArcPts[0].x, ghostArcPts[0].y)
            for (var g = 1; g < ghostArcPts.length; g++)
                ctx.lineTo(ghostArcPts[g].x, ghostArcPts[g].y)
            ctx.stroke()
            ctx.restore()
        }

        // 3. Terrain blocks: 48×48 fill + 2px top edge
        for (var row = 0; row < rows; row++) {
            for (var col = 0; col < cols; col++) {
                if (_terrain[row * cols + col]) {
                    var bx = col * bs
                    var by = row * bs
                    ctx.fillStyle = colTerrain
                    ctx.fillRect(bx, by, bs, bs)
                    ctx.fillStyle = colTerrainEdge
                    ctx.fillRect(bx, by, bs, 2)
                }
            }
        }

        // 4. Tanks: 40×20, HP bar, label
        for (var ti = 0; ti < tanks.length; ti++) {
            var tk = tanks[ti]
            var tc = (ti === 0) ? colP1 : colP2
            // center 40px tank in 48px column: left edge = tk.x + (48-40)/2 = tk.x + 4
            var tx = tk.x + 4
            var ty = tk.y - 20

            // body
            ctx.fillStyle = tc
            ctx.fillRect(tx, ty, 40, 20)

            // label — center of column = tk.x + 24
            ctx.fillStyle = tc
            ctx.font = "10px monospace"
            ctx.textAlign = "center"
            ctx.fillText("P" + (ti + 1), tk.x + 24, ty - 6)
        }

        // 5. Projectile (during animation)
        if (gamePhase === 2 && trajectoryPts.length > 0) {
            var frame = Math.min(_animFrame, trajectoryPts.length - 1)
            var proj  = trajectoryPts[frame]
            ctx.fillStyle = colProjectile
            ctx.beginPath()
            ctx.arc(proj.x, proj.y, 4, 0, 2 * Math.PI)
            ctx.fill()
        }

        // 6. Turn indicator top-center
        ctx.font = "bold 14px monospace"
        ctx.textAlign = "center"
        if (gameStatus === 1) {
            ctx.fillStyle = colP1
            ctx.fillText(">> P1 WINS <<", width / 2, 20)
        } else if (gameStatus === 2) {
            ctx.fillStyle = colP2
            ctx.fillText(">> P2 WINS <<", width / 2, 20)
        } else if (gamePhase === 1) {
            var pc = (activePlayer === 1) ? colP1 : colP2
            ctx.fillStyle = pc
            ctx.fillText("> P" + activePlayer + " AIM", width / 2, 20)
        }
    }

}
