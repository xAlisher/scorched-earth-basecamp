---
id: qml-canvas-game
title: QML Canvas game rendering — ghost arc, terrain mutation, animation timer
last_used: "2026-04-20"
created: "2026-04-20"
status: active
---

## Ghost arc pattern

Previous shot arc stays visible until next shot fires.

```qml
// In Main.qml
property var ghostArcPts: []

function onFire() {
    root.ghostArcPts = root.trajectoryPts   // save before computing new one
    root.trajectoryPts = Physics.trajectory(...)
    root.animFrame = 0
    root.gamePhase = 2
}

function onAnimationComplete() {
    root.ghostArcPts = root.trajectoryPts   // freeze final arc position
    root.projectile = null
}
```

```qml
// In GameCanvas.qml onPaint — draw ghost BEFORE terrain and projectile
function drawGhostArc(ctx) {
    if (root.ghostArcPts.length === 0) return
    ctx.save()
    ctx.setLineDash([4, 6])
    ctx.strokeStyle = "#2a2a4a"
    ctx.lineWidth = 1
    ctx.beginPath()
    for (var i = 0; i < root.ghostArcPts.length; i++) {
        var p = root.ghostArcPts[i]
        i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)
    }
    ctx.stroke()
    ctx.restore()
}
```

## Terrain array mutation — must copy + reassign

```qml
// WRONG — bindings don't update:
root.terrain[row * COLS + col] = false

// CORRECT:
var t = root.terrain.slice()
t[row * COLS + col] = false
root.terrain = t
gameCanvas.requestPaint()
```

## Animation timer

```qml
Timer {
    id: animTimer
    interval: 16; repeat: true
    running: root.gamePhase === 2
    onTriggered: {
        root.animFrame++
        if (root.animFrame >= root.trajectoryPts.length) {
            animTimer.stop()
            root.onAnimationComplete()
        } else {
            root.projectile = root.trajectoryPts[root.animFrame]
            gameCanvas.requestPaint()
        }
    }
}
```

## Canvas does NOT auto-repaint on property change

Always call `requestPaint()` explicitly after any state mutation.

## Avoid QtQuick.Shapes — use Canvas for all game-world drawing
