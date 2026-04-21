# Retro Log

## win 2026-04-20
scorched_earth_ui Main.qml complete: hot-seat game loop — initGame/onFire/onAnimationComplete, ghost arc management, keyboard tank movement, game-over overlay with new-game button; qmllint 0 errors 0 warnings across all 4 QML files; installed to LogosBasecamp plugins

## fail 2026-04-20
double-launch anti-pattern: using nohup...& multiple times without confirming previous instance died first caused 2 Basecamp instances. Root cause: pkill -f patterns (.LogosBasecamp.elf has leading dot, logos-basecamp-current.AppImage name mismatch) silently failed (exit 1), leaving first instance alive while second was spawned. Fix: always grep PIDs first, kill by PID explicitly, confirm count=0 before launching.

## fail 2026-04-20
ui_qml plugin silent sidebar miss — missing `variant` file containing "linux-amd64"; plugin directory looked correct, C++ module loaded fine, no error in logs — completely silent. Fix: echo -n "linux-amd64" > plugin_dir/variant. RETRO NOTE: research why variant is required (what in MainUIBackend reads it, what happens without it), add variant creation to dev-install-convention recipe and any new-module scaffold checklist so it's never forgotten again.

## fail 2026-04-20
QML uppercase property names crash silently: GameCanvas.qml used `BS`, `COLS`, `ROWS` as readonly property names. QML property names must start with lowercase — uppercase causes silent load failure ("Type unavailable"). Only caught by running qmlscene directly. Fix: rename to `bs`, `cols`, `rows` + replace_all usages.

## fail 2026-04-20
physics.js import blocked in QML sandbox: `import "physics.js" as Physics` caused silent UI load failure — no working plugin imports a .js file. Fix: inline the trajectory() function directly in Main.qml. physics.js stays in repo for determinism test (Epic 4) but is NOT imported at runtime.

## fail 2026-04-20
tankId 0-vs-1 index mismatch: C++ moveTank/processShot validate `tankId < 1` (1-indexed), but QML passed `activePlayer - 1` (0-indexed). Every call returned "invalid" silently — turn never advanced, terrain never destroyed, tanks never took damage. Fix: pass `activePlayer` (1 or 2) directly to C++ calls; use `activePlayer - 1` only for JS array indexing.

## fail 2026-04-20
terrainSnapY offset wrong: returned `row * blockSize - blockSize/2` placing tank bottom 24px above terrain surface. Fix: return `row * blockSize` — tank bottom aligns with terrain top pixel.

## fail 2026-04-21
ui_qml plugins installed to wrong dir: cp -r to modules/scorched_earth_ui/ instead of plugins/scorched_earth_ui/ — old QML stayed in plugins/, new files went nowhere useful, silent miss. Fix: always install ui_qml to ~/.local/share/Logos/LogosBasecamp/plugins/ not modules/. Add plugins/ to dev-install-convention recipe and module scaffold checklist.

## win 2026-04-20
hot-seat game loop fully working: turn advances P1↔P2, terrain blocks destroyed on hit, ghost arc visible, per-player angle/power persists across turns, space=fire, arrow keys move tank one grid step, uphill movement blocked, tank centered in grid column. All Epic 2 checklist items pass. — missing `variant` file containing "linux-amd64"; plugin directory looked correct, C++ module loaded fine, no error in logs — completely silent. Fix: echo -n "linux-amd64" > plugin_dir/variant. RETRO NOTE: research why variant is required (what in MainUIBackend reads it, what happens without it), add variant creation to dev-install-convention recipe and any new-module scaffold checklist so it's never forgotten again.
