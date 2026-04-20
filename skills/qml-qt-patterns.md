---
name: qml-qt-patterns
status: active
verified_date: 2026-04-15
verified_by_us: true
basecamp_version: "0.2.x"
note: Extends basecamp-skills/qml-patterns.md — game-specific only
---

# QML/Qt Patterns — Game-Specific

## gamePhase state machine

```
0 = idle       (mode unset, or waiting for opponent)
1 = aiming     (active player — sliders enabled, arrow keys live)
2 = animating  (projectile in flight — all controls locked)
3 = gameover   (win/loss overlay)
```

Gate all controls: `enabled: root.myTurn && root.gamePhase === 1`

## myTurn computation

```qml
// Hot-seat: always true when it's any player's turn
property bool myTurn: gamePhase === 1  // hotseat

// Multiplayer: only when it's this client's role
property bool myTurn: activePlayer === myRole && gamePhase === 1
```

## Inputs persist after shot

Do NOT reset aimAngle / aimPower after firing.
Player sees ghost arc of their shot and adjusts from previous values.
Only reset on newGame().

## Keys.onPressed requires focus: true on root Rectangle

```qml
Rectangle { id: root; focus: true
    Keys.onPressed: function(event) { ... }
}
```

## JS module qualified calls

```qml
import "qml/js/physics.js" as Physics
Physics.trajectory(...)   // always qualified
```
