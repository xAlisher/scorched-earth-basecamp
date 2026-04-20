# Claude Code Prompt: basecamp-scorched-earth
**Version:** 2.0  
**Date:** 2026-04-15  
**Status:** Ready to execute

---

## Design decisions — locked, do not deviate

| Decision | Answer |
|---|---|
| `scorched-earth/` state | Scaffolding only — folder exists, no real code yet |
| CMake pattern | Copy from keycard-basecamp (file provided in Task B) |
| Room connect | 6-char code, shared out of band, other player types it in |
| Visual style | Terminal / cypherpunk — dark, monospace, raw |
| Maps | One hard-coded stage, ship it |
| Debug mode | Auto-advance turn after shot lands — no button needed |
| Multiplayer | Same machine hot-seat first → Waku P2P next (architect for both) |
| Ghost arc | Previous shot arc stays visible until next shot fires, then replaced |
| Inputs after shot | Angle and power values stay in sliders — player adjusts from last values |
| Trajectory preview | None — fire and it flies. Ghost arc is the feedback. |
| Slider reset | Only on newGame() — never after individual shots |

---

## Mandatory reading — before any code or shell commands

Read ALL of these in full. They are ground truth. Do not invent patterns.

```
ARCHITECTURE_DISCOVERY.md       — module structure, delivery_module API, message schema, risk register
CHAT_UI_EXPLORATION.md          — QMetaObject::invokeMethod, DeliveryClient wrapper, mutex rules
CHAT_REPOS_EXPLORATION.md       — decision matrix, double-base64 decode, dedup via data[1]
```

Local reference implementations:
```
/home/alisher/basecamp-modules/logos-module-tictactoe   (branch: upstream-multiplayer)
/home/alisher/logos-chat-ui
/home/alisher/logos-chat-legacy-ui
/home/alisher/logos-chat-legacy-module
/home/alisher/basecamp-modules/keycard-basecamp/        (CMake pattern — primary reference)
/home/alisher/basecamp-modules/basecamp-skills/         (all .md files — read before any Basecamp call)
```

---

## Task A — Create GitHub repo

> ⚠️ `scorched-earth/` already exists as a scaffold. Do NOT recreate it. Build around it.

```bash
cd /home/alisher/basecamp-modules
gh repo create logos-co/basecamp-scorched-earth \
  --public \
  --description "Turn-based multiplayer artillery game — Logos Basecamp module" \
  --source . \
  --push
```

Create `README.md`:

```markdown
# basecamp-scorched-earth

Turn-based artillery game for [Logos Basecamp](https://github.com/logos-co/logos-app).  
Hot-seat single-player now. P2P multiplayer via Waku relay coming next.

**Status: experimental / dev-only** — pre-release Basecamp target. Not consumer-facing.

## Modules
- `scorched-earth/`     — C++ core plugin (game logic, physics, terrain)
- `scorched-earth-ui/`  — QML UI plugin (canvas rendering, turn management, multiplayer)

## Multiplayer (coming)
P2P via `delivery_module` (Waku relay). No central server.
Share a 6-char room code out of band to start a game.

## Build
Requires Nix. Top-level `CMakeLists.txt` builds both modules.

## Skills
Project-local skills in `skills/`. Complement — never duplicate — `basecamp-skills/`.

## Contributing
See `CONTRIBUTING.md` — specs-first, builder/verifier, qmllint enforced, no Sentry review.
```

---

## Task B — Top-level CMakeLists.txt

> Pattern source: keycard-basecamp/CMakeLists.txt (provided by developer).
> Adapt for scorched-earth — same structure, remove keycard-specific deps.

```cmake
cmake_minimum_required(VERSION 3.28)
project(basecamp-scorched-earth VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Find Qt6
find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(Qt6 OPTIONAL_COMPONENTS Test)

# No external libs for scorched-earth core:
# - Physics is pure math (no OpenSSL, no sodium, no pcsclite)
# - If a system lib is needed later: use pkg_check_modules pattern from keycard CMake

# Modules — same add_subdirectory pattern as keycard-basecamp
add_subdirectory(scorched-earth)
add_subdirectory(scorched-earth-ui)
```

### scorched-earth/CMakeLists.txt rules (keycard pattern):
- Build target: `scorched_earth_plugin` (shared lib)
- RPATH: `$ORIGIN` — same as keycard-core
- Install paths (two targets — Portable and Dev):
  - `~/.local/share/Logos/LogosBasecamp/modules/scorched-earth/`
  - `~/.local/share/Logos/LogosBasecampDev/modules/scorched-earth/`
- Pre-install cleanup: remove `scorched-earth.bak` and `scorched-earth.old` before installing
  (Lesson #33 from keycard-basecamp — stale backup dirs cause version conflicts in Basecamp)
- Kill command for dev cycle: `pkill -9 -f "logos_host.elf"` (not `pkill logos_host`)

---

## Task C — Project-local skills folder

Create `skills/` at repo root. Before creating any skill file, check
`/home/alisher/basecamp-modules/basecamp-skills/` — if the pattern is already
covered there, do NOT duplicate it. Reference it instead.

### skills/README.md

```markdown
# Project Skills

Patterns discovered during basecamp-scorched-earth development.
Complement — never duplicate — [basecamp-skills](https://github.com/logos-co/basecamp-skills).

| File | Covers | Duplicates basecamp-skills? |
|------|--------|----------------------------|
| delivery-module-messaging.md | double-base64, self-echo, event bridge | No — game additions |
| qml-canvas-game.md           | Canvas rendering, ghost arc, animation timer | No — game-specific |
| qml-qt-patterns.md           | Terrain array mutation, gamePhase machine | No — game-specific |
| headless-core-testing.md     | QtTest for core modules, determinism test | No — game-specific |

Last verified AppImage: (fill after first successful build)
```

### skills/delivery-module-messaging.md

```markdown
---
name: delivery-module-messaging
status: active
verified_date: 2026-04-15
verified_by_us: true
basecamp_version: "0.2.x"
source: logos-module-tictactoe (upstream/feat/delivery-multiplayer) + logos-chat-ui
---

# delivery_module Messaging

## Init (QML) — pollBusy guard mandatory

```qml
function enableMultiplayer() {
    if (root.pollBusy) return
    root.pollBusy = true
    Timer { singleShot: true; interval: 1; onTriggered: {
        logos.callModule("delivery_module", "createNode",
            ['{"logLevel":"INFO","mode":"Core","preset":"logos.dev","relay":true}'])
        logos.callModule("delivery_module", "start", [])
        logos.callModule("delivery_module", "subscribe", [root.contentTopic])
        logos.onModuleEvent("delivery_module", "messageReceived")
        root.multiplayerOn = true
        root.pollBusy = false
    }}
}
```

## Send — our base64 layer (delivery adds its own on top)

```qml
logos.callModule("delivery_module", "send",
    [topic, Qt.btoa(JSON.stringify(msgObj))])
```

## Receive — double decode + self-echo filter

```qml
Connections {
    target: typeof logos !== "undefined" ? logos : null
    function onModuleEventReceived(moduleName, eventName, data) {
        if (moduleName !== "delivery_module") return
        if (eventName !== "messageReceived") return
        if (root.ownPubKey !== "" && data[1] === root.ownPubKey) return  // self-echo
        var msg = JSON.parse(Qt.atob(Qt.atob(data[2])))
        // dispatch on msg.t
    }
}
```

## data[] layout
- data[0] = content topic
- data[1] = sender pubkey ← self-echo filter key
- data[2] = base64(base64(payload))

## Content topic naming
`/scorched-earth/1/room-{roomId}/json`
Always include room ID. Hardcoded topic = all players share one board.

## callModuleParse helper

```qml
function callModuleParse(raw) {
    try { var t = JSON.parse(raw); return typeof t === 'string' ? JSON.parse(t) : t }
    catch(e) { return null }
}
```

## C++ rules (from CHAT_UI_EXPLORATION.md)
- All onEvent callbacks: QMetaObject::invokeMethod(Qt::QueuedConnection)
- Capture QVariantList by VALUE in queued lambdas
- Defer start() via QTimer::singleShot(0, ...)
```

### skills/qml-canvas-game.md

```markdown
---
name: qml-canvas-game
status: active
verified_date: 2026-04-15
verified_by_us: true
basecamp_version: "0.2.x"
---

# QML Canvas — Game Rendering

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
    // ...
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
Always call requestPaint() explicitly after any state mutation.

## Avoid QtQuick.Shapes — use Canvas for all game-world drawing
```

### skills/qml-qt-patterns.md

```markdown
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
```

### skills/headless-core-testing.md

```markdown
---
name: headless-core-testing
status: active
verified_date: 2026-04-15
verified_by_us: true
basecamp_version: "0.2.x"
---

# Headless Core Module Testing

## CMakeLists.txt test binary

```cmake
find_package(Qt6 REQUIRED COMPONENTS Core Test)

qt_add_executable(tst_game
    tests/tst_game.cpp
    src/physics.cpp
    src/terrain.cpp
    src/game_plugin.cpp
)
target_link_libraries(tst_game PRIVATE Qt6::Core Qt6::Test)
target_include_directories(tst_game PRIVATE src)
add_test(NAME tst_game COMMAND tst_game)
```

## Test file pattern

```cpp
#include <QtTest>
#include "physics.h"
class TestGame : public QObject {
    Q_OBJECT
private slots:
    void tst_trajectory_upward();
    void tst_terrain_hit();
};
QTEST_MAIN(TestGame)
#include "tst_game.moc"
```

## Determinism test — physics.js output must equal physics.cpp output

```bash
node tests/determinism.mjs > /tmp/js.json
./result/bin/determinism_cpp > /tmp/cpp.json
diff /tmp/js.json /tmp/cpp.json   # must be empty
```

Non-empty diff = clients will desync in multiplayer. Fix before merging.
```

---

## Task D — GitHub labels, milestones, project board

```bash
gh label create "epic"        --color "#7B68EE" --description "Top-level epic"
gh label create "blocker"     --color "#FF0000" --description "Blocks other work"
gh label create "core"        --color "#F4A460" --description "C++ core module"
gh label create "qml"         --color "#00CED1" --description "QML UI module"
gh label create "multiplayer" --color "#FF69B4" --description "delivery_module / P2P"
gh label create "physics"     --color "#98FB98" --description "Projectile / terrain physics"
gh label create "testing"     --color "#DDA0DD" --description "Tests / qmllint / headless"
gh label create "infra"       --color "#778899" --description "Build / Nix / CI"
gh label create "retro"       --color "#FFD700" --description "Auto-retro summary post"
gh label create "skill"       --color "#20B2AA" --description "New pattern → skills/"

gh api repos/logos-co/basecamp-scorched-earth/milestones \
  --method POST -f title="v0.1.0 — Hot-seat playable" \
  -f description="C++ core builds, QML renders, full hot-seat game loop working"

gh api repos/logos-co/basecamp-scorched-earth/milestones \
  --method POST -f title="v0.2.0 — Waku multiplayer" \
  -f description="Two machines, same room code, full game over delivery_module"
```

---

## Task E — Epics

Create these 5 epics first. Record their issue numbers before creating sub-issues.

### Epic 1: Build system and core scaffold
```
Title: [EPIC] Build system — CMake (keycard pattern), core scaffold, Basecamp load
Labels: epic, core, infra
Milestone: v0.1.0

Scope:
- Top-level CMakeLists.txt (keycard-basecamp pattern)
- scorched-earth/CMakeLists.txt (RPATH, install, stale-dir cleanup)
- game_interface.h (IID: org.logos.ScorchedEarthInterface)
- physics.cpp + terrain.cpp (hardcoded layout, pure math)
- game_plugin.cpp (newGame, moveTank, processShot, getState, emitEvent)
- metadata.json (Basecamp 0.2.0 format)

Exit criteria:
[ ] nix build succeeds
[ ] libscorched_earth_plugin.so in result/lib/
[ ] Module loads in Basecamp without crash
[ ] newGame returns {terrain:[200 bools], tank1:{x,y,hp}, tank2:{x,y,hp}}
[ ] processShot returns {hit, removedBlocks, seq, status}
[ ] stale .bak/.old dirs cleaned on install

Auto-retro posted when epic closes.
```

### Epic 2: QML UI — terminal aesthetic, ghost arc, hot-seat auto-advance
```
Title: [EPIC] QML UI — canvas, ghost arc, inputs persist, hot-seat auto-advance
Labels: epic, qml, physics
Milestone: v0.1.0

Scope:
- metadata.json (0.2.0: "view":"Main.qml", "main":{})
- Terminal/cypherpunk palette (#0d0d0d, #00ff41, monospace)
- GameCanvas.qml — terrain, tanks, ghost arc (dim dotted), projectile
- AimControl.qml — sliders persist after shot, reset only on newGame
- physics.js — constants must match physics.cpp exactly
- Main.qml — auto-advance turn, ghost arc management, inputs preserved
- qmllint passing on ALL QML files

Exit criteria:
[ ] Terrain renders (hardcoded layout)
[ ] Tank moves on surface, clamped at boundaries
[ ] FIRE: projectile animates, block disappears on hit
[ ] Ghost arc stays visible as dim dotted line after shot
[ ] Ghost arc replaced when next shot fires
[ ] Angle/power values stay in sliders after shot
[ ] Turn auto-advances after animation completes
[ ] Game over shown in monospace terminal style
[ ] New game resets terrain, tanks, ghost arc, sliders to defaults
[ ] qmllint clean

Auto-retro posted when epic closes.
```

### Epic 3: Waku multiplayer via delivery_module
```
Title: [EPIC] Multiplayer — P2P via delivery_module, room code, hot-seat preserved
Labels: epic, qml, multiplayer
Milestone: v0.2.0

Scope:
- delivery.js + messages.js
- RoomPanel.qml — Create Room, Join by code, Connect/Disconnect
- Main.qml multiplayer wiring (self-echo filter, pollBusy guard)
- GAME_START, SHOT, TURN_ACK flow
- Hot-seat mode preserved — multiplayer is additive

Exit criteria:
[ ] Two instances join via 6-char code
[ ] P1 fires → P2 sees identical animation + ghost arc
[ ] Turn advances correctly on both
[ ] No self-echo
[ ] 5 consecutive shots without desync
[ ] Hot-seat still works with multiplayer off

Auto-retro posted when epic closes.
```

### Epic 4: Testing infrastructure
```
Title: [EPIC] Testing — qmllint CI, headless QtTest, determinism, manual protocol
Labels: epic, testing, infra
Milestone: v0.1.0

Exit criteria:
[ ] CI runs qmllint on every PR (warnings = errors)
[ ] 9 QtTest unit tests pass headless
[ ] Determinism test passes (js === cpp byte-for-byte)
[ ] Manual test protocol documented

Auto-retro posted when epic closes.
```

### Epic 5: Polish and docs
```
Title: [EPIC] Polish — win screen, new game, README complete
Labels: epic, qml
Milestone: v0.2.0

Exit criteria:
[ ] Full game playable start to finish, solo and multiplayer
[ ] New game works in both modes
[ ] README sufficient for new contributor to build and test

Auto-retro posted when epic closes.
```

---

## Task F — Sub-issues

Each body must contain "Part of #N" with correct epic number.

---

### Epic 1 sub-issues

**[BLOCKER] Verify delivery_module present in target Basecamp AppImage**
```
Labels: blocker, multiplayer
Milestone: v0.2.0
Part of: #<epic-1>

In Basecamp probe or QML console:
logos.callModule("delivery_module","createNode",
  ['{"logLevel":"INFO","mode":"Core","preset":"logos.dev","relay":true}'])
ls ~/.local/share/Logos/LogosBasecamp/modules/ | grep delivery

Document result. If absent: Epic 3 fully blocked.
```

**Top-level CMakeLists.txt — keycard-basecamp pattern**
```
Labels: core, infra
Milestone: v0.1.0
Part of: #<epic-1>

find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(Qt6 OPTIONAL_COMPONENTS Test)
add_subdirectory(scorched-earth)
add_subdirectory(scorched-earth-ui)

No external libs. If one is needed later: pkg_check_modules pattern from keycard CMake.
```

**scorched-earth/CMakeLists.txt — module build and install**
```
Labels: core, infra
Milestone: v0.1.0
Part of: #<epic-1>

Adapt from keycard-core/CMakeLists.txt:
- Shared lib target: scorched_earth_plugin
- RPATH: $ORIGIN
- Install to Portable: ~/.local/share/Logos/LogosBasecamp/modules/scorched-earth/
- Install to Dev:      ~/.local/share/Logos/LogosBasecampDev/modules/scorched-earth/
- Pre-install: remove scorched-earth.bak and scorched-earth.old (Lesson #33)
```

**Implement game_interface.h**
```
Labels: core
Milestone: v0.1.0
Part of: #<epic-1>

IID: "org.logos.ScorchedEarthInterface"
Q_INVOKABLE:
  QString newGame(int cols, int rows, int windForce)
  QString getState()
  int     moveTank(int tankId, int direction)   // -1=left +1=right
  QString processShot(int tankId, float angle, float power)
  int     gameStatus()   // 0=ongoing 1=p1wins 2=p2wins
  int     activePlayer() // 1 or 2
Signal: void eventResponse(const QString& name, const QVariantList& data)
```

**Implement terrain.h / terrain.cpp — hardcoded stage**
```
Labels: core, physics
Milestone: v0.1.0
Part of: #<epic-1>

20 cols × 10 rows. BLOCK_SIZE=48. Flat bool vector.

Layout (O=alive .=air, row 0=top):
Row 0-1: all air
Row 2:   . . . . O O . . . . . . O O . . . . . .
Row 3:   . . O O O O . . . . . . O O O O . . . .
Row 4:   . O O O O O . . . . . . O O O O O . . .
Row 5:   O O O O O O . . O O O O . . O O O O O O
Row 6-9: all O

Tank 1: col 2 (x=96). Tank 2: col 17 (x=816).
Tank y: scan column downward, find first alive row → y = row*48 - 24.
```

**Implement physics.h / physics.cpp**
```
Labels: core, physics
Milestone: v0.1.0
Part of: #<epic-1>

Constants: GRAVITY=0.3f, BLOCK_SIZE=48, CANVAS_WIDTH=960, CANVAS_HEIGHT=480
trajectory(startX, startY, angleDeg, power) → vector<PhysPoint>
  vx=cos(rad)*power*0.15, vy=-sin(rad)*power*0.15, GRAVITY per tick
firstCollision(pts, terrain, cols, rows, tankPositions, blockSize) → Collision
  INTEGER arithmetic for collision. Float for path coords only.
  Tank hit zone: abs(px-tankX) < BLOCK_SIZE && abs(py-tankY) < BLOCK_SIZE

CRITICAL: constants must be identical to physics.js. Determinism test verifies.
```

**Implement game_plugin.cpp**
```
Labels: core
Milestone: v0.1.0
Part of: #<epic-1>

State: vector<bool> terrain, Tank tanks[2]{x,y,hp}, activePlayer=1, turnSeq=0, status=0

newGame(): reset terrain to hardcoded layout, tanks to initial positions, hp=100
moveTank(id,dir): ±BLOCK_SIZE, clamp [0,19*48], terrain-snap y
processShot(tankId,angle,power):
  → trajectory() + firstCollision()
  → terrain hit: block=false
  → tank hit: hp-=25; hp<=0 → status=winner
  → flip activePlayer (1↔2), increment turnSeq
  → emit eventResponse("stateChanged",[getState()])
  → return {hit, tankId, removedBlocks:[[col,row],...], seq, status}
emitEvent: logosAPI->getClient("scorched_earth")->onEventResponse(this,name,data)
```

**metadata.json (Basecamp 0.2.0)**
```
Labels: core, infra
Milestone: v0.1.0
Part of: #<epic-1>

{
  "name": "scorched_earth",
  "version": "0.1.0",
  "type": "core",
  "category": "game",
  "description": "Scorched Earth — turn-based artillery game",
  "main": "scorched_earth_plugin",
  "dependencies": []
}

Verify format against: cat /tmp/.mount_logos-*/usr/plugins/counter_qml/manifest.json
```

**Verify nix build and Basecamp load**
```
Labels: core, infra, testing
Milestone: v0.1.0
Part of: #<epic-1>

nix build (top-level)
ls result/lib/libscorched_earth_plugin.so
Load in Basecamp → module in list
logos.callModule("scorched_earth","newGame",[20,10,0]) → valid JSON
Document AppImage version as comment.
```

---

### Epic 2 sub-issues

**Scaffold scorched-earth-ui/**
```
Labels: qml, infra
Milestone: v0.1.0
Part of: #<epic-2>

metadata.json:
  "type": "ui_qml"
  "view": "Main.qml"   ← string
  "main": {}           ← EMPTY OBJECT (0.2.0 format — not a string)
  "dependencies": ["scorched_earth"]
  "category": "games"

icons/scorched-earth.png (28×28 solid #00ff41 placeholder)
Empty stub QML files — run qmllint on all, must pass.
Verify module loads in Basecamp (blank screen acceptable).
```

**Define terminal/cypherpunk colour palette**
```
Labels: qml
Milestone: v0.1.0
Part of: #<epic-2>

Define as named constants at top of Main.qml.
No Logos.Theme. No QtGraphicalEffects. All hardcoded.

background:   #0d0d0d   near-black
surface:      #111111
border:       #1a1a1a
terrain:      #1a3a1a   dark green block
terrain-edge: #00ff41   bright green 2px top highlight
tank-p1:      #00ff41   bright green
tank-p2:      #ff4444   red
projectile:   #ffff00   yellow
ghost-arc:    #2a2a4a   dim blue-grey (dotted line)
text:         #c0c0c0   silver
accent:       #00ff41
muted:        #444444
danger:       #ff4444

Font: monospace throughout (Qt built-in — no external fonts)
```

**Implement physics.js — mirror C++ exactly**
```
Labels: qml, physics
Milestone: v0.1.0
Part of: #<epic-2>

Constants MUST match: GRAVITY=0.3, BLOCK_SIZE=48, COLS=20, ROWS=10
CANVAS_WIDTH=960, CANVAS_HEIGHT=480

trajectory() and firstCollision() — identical logic to physics.cpp.
Math.floor for collision checks (integer only).

Epic 4 determinism test diffs this against C++ output byte-for-byte.
```

**Implement GameCanvas.qml — terrain, tanks, ghost arc, projectile**
```
Labels: qml
Milestone: v0.1.0
Part of: #<epic-2>

Canvas 960×480. Terminal aesthetic. onPaint draw order:

1. Background fillRect #0d0d0d
2. Ghost arc: ctx.setLineDash([4,6]), strokeStyle #2a2a4a, lineWidth 1
   — draw from root.ghostArcPts if non-empty (before terrain so it's behind)
3. Terrain blocks: 48×48, fill #1a3a1a, top-edge 2px #00ff41
4. Tanks: 40×20 fillRect. P1: #00ff41, P2: #ff4444
   HP bar above (40px, proportional, green→red)
   Label "P1"/"P2" above HP bar, monospace
5. Projectile: circle r=4, #ffff00 (only if non-null)
6. Turn indicator top-center monospace:
   "> P1 AIM" / "> P2 AIM" / "> WAITING" / ">> P1 WINS <<"

Animation Timer inside: interval 16, running: gamePhase===2
  onTriggered: animFrame++ → requestPaint → emit animationComplete

No QtQuick.Shapes. No QtGraphicalEffects.
Run qmllint — 0 errors, 0 warnings.
```

**Implement AimControl.qml — sliders persist after shot**
```
Labels: qml
Milestone: v0.1.0
Part of: #<epic-2>

Properties: myTurn:bool, aimAngle:real, aimPower:real
Signals: fireClicked(), aimAngleChanged(real), aimPowerChanged(real)

Terminal style layout:
  "> ANGLE: 045°"   Slider 0–180
  "> POWER: 075"    Slider 0–100
  "[ FIRE ]"        Button

All controls: enabled: myTurn && root.gamePhase === 1
DO NOT reset slider values after shot. Values persist.
Reset only on newGame() call from Main.qml.
Run qmllint — 0 errors.
```

**Implement RoomPanel.qml — stub**
```
Labels: qml
Milestone: v0.1.0
Part of: #<epic-2>

Stub: Text "> MULTIPLAYER: V0.2"
Full implementation in Epic 3. Run qmllint — must pass.
```

**Implement Main.qml — full hot-seat game loop**
```
Labels: qml
Milestone: v0.1.0
Part of: #<epic-2>

State properties:
  activePlayer:1, gamePhase:0, terrain:[], tanks:[]
  turnSeq:0, gameStatus:0
  myRole:0        // 0=hotseat, 1=P1 network, 2=P2 network
  multiplayerOn:false, pollBusy:false, ownPubKey:""
  trajectoryPts:[], ghostArcPts:[], animFrame:0, projectile:null
  aimAngle:45, aimPower:50    // persist after shot, reset on newGame only
  myTurn: gamePhase===1       // hotseat: always true on aiming phase

Helpers: callModuleParse(), randomRoomId()

Lifecycle:
  Component.onCompleted → Timer{singleShot:true;interval:1} → initGame()
  initGame(): callModule newGame, parse, set terrain+tanks, gamePhase=1

onFire():
  1. root.ghostArcPts = root.trajectoryPts   // save previous arc
  2. root.trajectoryPts = Physics.trajectory(tank.x, tank.y, aimAngle, aimPower)
  3. root.animFrame = 0, root.gamePhase = 2
  4. If multiplayerOn: Delivery.send SHOT
  5. processShot via callModule → store result

onAnimationComplete():
  1. root.ghostArcPts = root.trajectoryPts   // freeze arc as ghost
  2. root.projectile = null
  3. getState() → sync terrain, tanks, activePlayer
  4. gameStatus !== 0 → gamePhase=3
  5. gameStatus === 0 → gamePhase=1  // auto-advance — hot-seat and multiplayer
  6. If multiplayerOn: send TURN_ACK

Arrow keys (Keys.onPressed, focus:true on root):
  Left/Right → moveTank(activePlayer, dir) if gamePhase===1
  Terrain array update: .slice() + reassign (NOT in-place mutation)

JS imports at top:
  import "qml/js/physics.js" as Physics
  import "qml/js/delivery.js" as Delivery
  import "qml/js/messages.js" as Messages

Run qmllint Main.qml — 0 errors.
```

**Manual test — hot-seat full game**
```
Labels: qml, testing
Milestone: v0.1.0
Part of: #<epic-2>

Close only when ALL pass:
[ ] Module loads without error
[ ] Terrain renders matching hardcoded layout
[ ] Arrow keys: tank moves on terrain surface, stops at boundary
[ ] Angle slider: value updates, stays after shot
[ ] Power slider: value updates, stays after shot
[ ] FIRE: projectile animates along arc
[ ] Block hit: block disappears
[ ] Ghost arc: dim dotted line of previous shot visible after animation
[ ] Ghost arc: replaced when next shot fires (not accumulated)
[ ] Turn: auto-advances — other side moves/fires next
[ ] Tank hit: game over overlay shown in monospace
[ ] New game: terrain, tanks, ghost arc cleared; sliders reset to 45/50
[ ] AppImage version documented as comment
```

---

### Epic 3 sub-issues

**Implement delivery.js and messages.js**
```
Labels: qml, multiplayer
Milestone: v0.2.0
Part of: #<epic-3>

delivery.js — copy EXACTLY from skills/delivery-module-messaging.md:
  enable(), disable(), send() [Qt.btoa single layer], decode() [Qt.atob double]
  senderKey(data) → data[1]

messages.js:
  TYPE_GAME_START="gs", TYPE_SHOT="sh", TYPE_TURN_ACK="ak"
  makeGameStart(roomId, wind, role)
  makeShot(angle, power, seq)
  makeTurnAck(seq, hitTank, tankId)
```

**Implement RoomPanel.qml — full multiplayer UI**
```
Labels: qml, multiplayer
Milestone: v0.2.0
Part of: #<epic-3>

Terminal style. Signals: createRoomClicked(), joinRoomClicked(string), multiplayerToggled()

Layout (monospace):
  "> ROOM: AB3X7Q"           visible when roomId set
  "[ CREATE ROOM ]"          visible when myRole===0
  "> JOIN: [______] [JOIN]"  TextField + button
  "[ CONNECT ] / [ DISCONNECT ]" toggle
  "> YOU ARE P1 / P2"        visible when myRole>0
  "> WAITING FOR OPPONENT"   visible when multiplayerOn && gamePhase===0

Run qmllint — 0 errors.
```

**Wire delivery_module in Main.qml**
```
Labels: qml, multiplayer
Milestone: v0.2.0
Part of: #<epic-3>

enableMultiplayer(): pollBusy guard + Timer singleShot
  → Delivery.enable() → try getLocalPeerInfo() for ownPubKey
disableMultiplayer(): Delivery.disable()
onCreateRoom(): randomRoomId → contentTopic="/scorched-earth/1/room-{id}/json"
  → enableMultiplayer() → Timer 3s → GAME_START → gamePhase=1
onJoinRoom(code): set roomId+topic → enableMultiplayer() → gamePhase=0

Event bridge Connections (ARCHITECTURE_DISCOVERY Q4 pattern exactly).
handleDeliveryMessage():
  → self-echo filter first
  → decode → dispatch on msg.t

In multiplayer mode, onAnimationComplete:
  gamePhase=1 only if activePlayer===myRole (not always like hot-seat)

Run qmllint — 0 errors.
```

**SHOT + TURN_ACK flow**
```
Labels: qml, multiplayer
Milestone: v0.2.0
Part of: #<epic-3>

onFire() multiplayer: ghost saved → trajectoryPts computed
  → Delivery.send SHOT before processShot (peer computes same result)
applyShot(angle, power, seq): remote shot handler
  → same Physics.trajectory + firstCollision locally
  → processShot via callModule → animate → onAnimationComplete
onAnimationComplete(): send TURN_ACK after applying
```

**Self-echo filter — verify and document**
```
Labels: qml, multiplayer, testing
Milestone: v0.2.0
Part of: #<epic-3>

Does getLocalPeerInfo() exist in delivery_module?
  Yes: ownPubKey = info.peerId, filter data[1]===ownPubKey
  No: sent-seq Set fallback

Test: fire 3 shots, confirm none applied twice.
Document in skills/delivery-module-messaging.md.
```

**Manual test — two-instance multiplayer**
```
Labels: multiplayer, testing
Milestone: v0.2.0
Part of: #<epic-3>

[ ] Instance A: Create Room → 6-char code shown
[ ] Instance B: Enter code, Join
[ ] Both: role/status shown
[ ] P1 fires → P2 sees identical animation + ghost arc
[ ] Block disappears on both
[ ] Turn advances: P2 active, P1 locked
[ ] P2 fires → P1 sees identical animation
[ ] Game ends same on both
[ ] 5 consecutive shots without desync
[ ] Hot-seat still works with multiplayer off
[ ] AppImage version documented
```

---

### Epic 4 sub-issues

**qmllint GitHub Actions CI**
```
Labels: testing, infra
Milestone: v0.1.0
Part of: #<epic-4>

.github/workflows/qmllint.yml:
  name: QML Lint
  on: [push, pull_request]
  jobs:
    qmllint:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - run: sudo apt-get install -y qt6-base-dev qt6-declarative-dev
        - run: find scorched-earth-ui -name "*.qml" | xargs qmllint

Warnings = errors. Fail on any.
```

**9 headless QtTest unit tests**
```
Labels: testing, core
Milestone: v0.1.0
Part of: #<epic-4>

scorched-earth/tests/tst_game.cpp. No Basecamp.

  tst_trajectory_upward: angle=90, power=50 → pts[1].y < pts[0].y
  tst_trajectory_bounded: exits canvas or oob on any shot
  tst_terrain_hit: aimed at known alive block → TERRAIN at correct col/row
  tst_terrain_miss: aimed at known empty col → no TERRAIN there
  tst_tank_hit: aimed at tank position → TANK collision
  tst_block_removed: after processShot hit → getState() block=false
  tst_turn_advances: after processShot → activePlayer flips 1→2→1→2
  tst_moveTank_clamp_left: from col 0, dir=-1 → x stays 0
  tst_moveTank_clamp_right: from col 19, dir=+1 → x stays 19*48

All 9 must pass. Add to CMakeLists.txt via add_test().
```

**Determinism test — physics.js === physics.cpp**
```
Labels: testing, physics
Milestone: v0.1.0
Part of: #<epic-4>

tests/determinism.mjs: load physics.js → trajectory(96,192,45,75) → JSON stdout
tests/determinism_cpp.cpp: same via Physics:: → same JSON stdout

CI: diff both outputs. Must be empty. Non-empty = multiplayer desync.
```

**Manual test protocol document**
```
Labels: testing
Milestone: v0.1.0
Part of: #<epic-4>

docs/manual-test-protocol.md
Sections: Environment, Hot-seat checklist, Multiplayer checklist,
Known issues, How to update skills/ when new patterns discovered.
Update after every AppImage upgrade.
```

**qmllint pre-commit hook**
```
Labels: testing, infra
Milestone: v0.1.0
Part of: #<epic-4>

.githooks/pre-commit:
  #!/bin/sh
  find scorched-earth-ui -name "*.qml" | xargs qmllint
  [ $? -ne 0 ] && echo "qmllint failed" && exit 1

CONTRIBUTING + README: git config core.hooksPath .githooks
```

---

### Epic 5 sub-issues

**Game over screen and new game**
```
Labels: qml
Milestone: v0.2.0
Part of: #<epic-5>

gamePhase===3: Canvas overlay ">> PLAYER N WINS <<" monospace, large
"[ NEW GAME ]" resets:
  terrain, tanks, ghostArcPts=[], trajectoryPts=[], projectile=null
  activePlayer=1, gamePhase=1, gameStatus=0
  aimAngle=45, aimPower=50   ← ONLY reset here, not after individual shots
Multiplayer: also send GAME_START.
```

**README complete**
```
Labels: infra
Milestone: v0.2.0
Part of: #<epic-5>

Sections: Requirements, Build (Nix), Load in Basecamp,
Hot-seat play, Multiplayer play, Architecture, Known issues, Contributing.
```

---

## Task G — Auto-retro after each epic closes

After all sub-issues of an epic close, post a retro as a new `retro`-labelled issue.

```bash
gh issue create \
  --title "[RETRO] Epic N — <title>" \
  --label "retro" \
  --body "$(cat <<'EOF'
## Auto-retro: Epic N
**Date:** <date>
**AppImage version:** <version>

### ✅ Wins
### ❌ Fails / surprises
### ⚠️ Deviations from spec
### 🧠 New patterns found
### 📁 Skills updated
### 🔜 Carries forward to next epic
EOF
)"
```

---

## Task H — CONTRIBUTING.md

```markdown
# Contributing

## Workflow (field-craft)
Specs-first, builder/verifier via GitHub issues.

### Before writing code
Open an issue: what, which epic (Part of #N), exit criteria.

### Branch naming
feat/<issue-number>-short-description

### PR rules
- Closes #N in description
- qmllint must pass (CI enforces)
- New C++ logic = new test in tst_game.cpp
- Manual checklist updated if UI changed

### No Sentry review
No existing users. Move fast.

## qmllint
```bash
find scorched-earth-ui -name "*.qml" | xargs qmllint
find scorched-earth-ui -name "*.qml" | xargs qmllint --json -   # agent-friendly
```
Install hook: git config core.hooksPath .githooks

## Headless tests
```bash
cd scorched-earth && nix build && ./result/bin/tst_game
```

## Skills
New pattern found → check basecamp-skills/ first → if game-specific, add to skills/.
Include AppImage version in frontmatter. Reference in PR description.
```

---

## Task I — Final verification

```bash
gh repo view logos-co/basecamp-scorched-earth
gh issue list --limit 50
gh label list
gh milestone list
```

Expected: 5 epics + ~24 sub-issues = ~29 total. Report URL and count.
