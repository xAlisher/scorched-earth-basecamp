# Scope of Work — Scorched Earth Multiplayer via delivery_module

_Created: 2026-04-22_
_Triggered by: delivery_module v1.1.0 release + tictactoe PR #5 confirming the pattern works._

---

## Goal

Wire `delivery_module` v1.1.0 into the scorched-earth C++ core to enable P2P turn-based
multiplayer. Players share a room/content-topic code out of band; game moves are
published/subscribed over `logos.dev` via delivery_module IPC.

Closes: scorched-earth issue #38.

---

## Out of scope

- Room matchmaking UI (separate issue)
- Spectator mode
- Reconnect / resume after disconnect
- RLN / TWN fleet (logos.dev only for now)

---

## Work items

### 1. Update flake + regenerate API headers

- Bump `logos-delivery-module` to `github:logos-co/logos-delivery-module/1.1.0`
- Run `nix flake update logos-delivery-module`
- Regenerate `src/generated/delivery_module_api.h/.cpp`
- Fix any `bool` → `LogosResult` call sites in existing code
- Add manual `follows` wiring in `flake.nix` (module-builder issue #83 not fixed yet)
- Add `"delivery_module"` to `metadata.json` dependencies

**Skill:** `docs/skills/delivery-module-multiplayer.md` — flake wiring section

---

### 2. Add DeliveryClient wrapper in C++ core

New file: `src/core/DeliveryClient.h/.cpp`

Responsibilities:
- Hold `DeliveryModule*` (generated IPC client)
- `init(contentTopic, tcpPort, discv5UdpPort)` → createNode + start + subscribe
- `sendMove(QJsonObject move)` → publish serialised JSON
- `onMoveReceived` signal → emitted on incoming message event
- Parse `LogosResult` on every call; surface errors via signal

**Skill:** `docs/skills/delivery-module-multiplayer.md` — node init + send/receive sections

---

### 3. Wire DeliveryClient into ScorchedEarthPlugin

- Instantiate `DeliveryClient` in `ScorchedEarthPlugin::initLogos`
- Expose `Q_INVOKABLE QString startMultiplayer(const QString& roomCode)` — derives
  content topic from room code, calls `DeliveryClient::init`
- Connect `DeliveryClient::onMoveReceived` → game logic handler
- `Q_INVOKABLE QString sendMove(const QString& moveJson)` — delegates to DeliveryClient

---

### 4. QML bindings

- `startMultiplayer(roomCode)` — called from lobby screen
- `onRemoteMoveReceived(moveJson)` — signal hooked in QML to apply opponent move
- No delivery logic in QML (issue #38 explicitly moves it to C++)

---

### 5. File-based logging

- Add `FileLogger` utility (or reuse if already present) for delivery-path events
- Log: node start, subscribe, every publish, every received message, all `LogosResult` errors
- Required because AppImage swallows stderr (basecamp issue #163)

---

### 6. Testing

- Headless test: two `logoscore` instances, each loading scorched-earth + delivery_module,
  exchange a move sequence over `logos.dev`
- Reference: `basecamp-skills/skills/logoscore-headless-testing.md`
- Port conflict workaround: assign explicit non-conflicting ports until port-0 fix lands
  (delivery-module issue #24)

---

## Blockers / known issues

| Blocker | Workaround |
|---------|-----------|
| `createNode` rejects port 0 (#24) | Use explicit ports (30305 / 9010) |
| `mkLogosModule` missing delivery follows (#83) | Add `follows` manually in flake.nix |
| Plugin stderr swallowed in AppImage (#163) | File-based logging |

---

## Reference

- Working implementation: `https://github.com/fryorcraken/logos-module-tictactoe/pull/5`
- Key file: `tictactoe/src/tictactoe_plugin.cpp#L89`
- Delivery skill: `docs/skills/delivery-module-multiplayer.md`
