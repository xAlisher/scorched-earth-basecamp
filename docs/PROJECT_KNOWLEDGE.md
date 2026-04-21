# Scorched Earth — Project Knowledge

Accumulated lessons, patterns, and pitfalls. Platform-wide learnings go to
`~/basecamp/basecamp-skills/skills/`; process learnings go to `~/fieldcraft/protocols/`.

---

## Build & Installation

### Q_PLUGIN_METADATA FILE must be `metadata.json`
`logos_module()` copies `metadata.json` to the build dir for moc. Any other filename
(e.g. `plugin_metadata.json`) causes nix build failure:
`Plugin Metadata file 'plugin_metadata.json' does not exist`.

### lgpm install: ui_qml variant must be reset after install
lgpm writes `variant = linux-amd64-dev` for plugins. Basecamp UI loader expects
`linux-amd64`. After every lgpm install of `scorched_earth_ui`:
```bash
echo -n "linux-amd64" > ~/.local/share/Logos/LogosBasecamp/plugins/scorched_earth_ui/variant
rm -rf ~/.cache/Logos/LogosBasecamp/qmlcache/
```

### nix bundle for QML modules: explicit package attr required
`nix bundle --bundler github:logos-co/nix-bundle-lgx#dual .` fails (default output is
`app`, not derivation). Use:
```bash
nix bundle --bundler github:logos-co/nix-bundle-lgx#dual .#packages.x86_64-linux.default
```

### ui_qml plugins install to `plugins/`, not `modules/`
Core `.so` → `~/.local/share/Logos/LogosBasecamp/modules/scorched_earth/`
QML plugin  → `~/.local/share/Logos/LogosBasecamp/plugins/scorched_earth_ui/`

---

## QML Patterns

### QML property names must start with lowercase
`BS`, `COLS`, `ROWS` as `readonly property` names cause silent load failure
("Type unavailable"). Use `bs`, `cols`, `rows`.

### Do not import .js files in QML
`import "physics.js" as Physics` causes silent UI load failure — no working Basecamp
plugin imports a `.js` file at runtime. Inline any needed logic in the QML file.
`physics.js` is kept in `qml/` for determinism reference (Epic 4) but is NOT imported.

### tankId convention: 1-indexed
C++ `moveTank`/`processShot` validate `tankId < 1` — they expect 1-indexed IDs (1 or 2).
QML uses `activePlayer` (1 or 2) directly. Only subtract 1 for JS array indexing.

---

## Game Logic

### terrainSnapY: return `row * blockSize` (not `row * blockSize - blockSize/2`)
Subtracting `blockSize/2` places tank bottom 24px above terrain surface. The correct
formula places the tank bottom flush with the terrain top pixel.

### P2P multiplayer: delivery_module dependency
P2P mode uses `delivery_module` for room create/join. This dependency must be running
in Basecamp for the room panel to work.

---

## Module Architecture

### Two separate flakes, two separate lgx packages
- `scorched-earth/` → `mkLogosModule` → installs as core module
- `scorched-earth-ui/` → `mkLogosQmlModule` → installs as ui_qml plugin

Both must be installed for the module to appear and load.

### All QML components live in `scorched-earth-ui/qml/`
`mkLogosQmlModule` only bundles a single file when `view` is at project root.
Moving to `qml/` subdir with `"view": "qml/Main.qml"` packages all components.
