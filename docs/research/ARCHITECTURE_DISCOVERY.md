---
name: scorched-earth-architecture-discovery
description: Full architecture discovery for Logos Basecamp Scorched Earth multiplayer module — findings from TicTacToe multiplayer branch + delivery_module P2P pattern + complete Scorched Earth build plan
type: project
basecamp_version: "0.2.x"
verified_date: "2026-04-15"
status: active
source: ours
verified_by_us: true
our_notes: "2026-04-15: Written from direct source-code analysis of upstream/feat/delivery-multiplayer branch of fryorcraken/logos-module-tictactoe. Local path: /home/alisher/basecamp-modules/logos-module-tictactoe branch upstream-multiplayer. This is the first confirmed P2P multiplayer pattern in the Basecamp ecosystem."
---

# Scorched Earth Module — Architecture Discovery Report

**Date:** 2026-04-15
**Reference repo:** `fryorcraken/logos-module-tictactoe`
**Branch analysed:** `upstream/feat/delivery-multiplayer` (local: `upstream-multiplayer`)
**Local clone:** `/home/alisher/basecamp-modules/logos-module-tictactoe`
**Key commits:**
- `3342145` — QML UI: add experimental multiplayer via delivery module
- `605bd4c` — C++ UI: add experimental multiplayer via delivery module

---

## Repository Layout (multiplayer branch)

```
logos-module-tictactoe/
├── tictactoe/                        # CORE MODULE — C/C++ game logic
│   ├── metadata.json                 # type: "core"
│   ├── CMakeLists.txt
│   ├── flake.nix
│   ├── lib/
│   │   ├── libtictactoe.h            # C API (enums + opaque handle)
│   │   └── libtictactoe.c            # Pure C implementation
│   └── src/
│       ├── tictactoe_interface.h     # Q_INVOKABLE abstract interface
│       ├── tictactoe_plugin.h        # Concrete plugin class
│       └── tictactoe_plugin.cpp      # Implementation + eventResponse emit
│
├── tictactoe-ui-cpp/                 # C++ WIDGET UI — uses protobuf
│   ├── metadata.json                 # type: "ui" (C++ widget, not QML)
│   ├── CMakeLists.txt                # protoc code-gen step included
│   ├── proto/
│   │   └── tictactoe.proto           # ← NEW in multiplayer branch
│   ├── interfaces/
│   │   └── IComponent.h
│   └── src/
│       ├── tictactoe_ui_interface.h
│       ├── tictactoe_ui_plugin.h
│       ├── tictactoe_ui_plugin.cpp   # createWidget() / destroyWidget()
│       ├── tictactoe_backend.h       # LogosModules wrapper + delivery IPC
│       └── tictactoe_backend.cpp     # ← NEW full multiplayer logic
│
└── tictactoe-ui-qml/                 # QML UI — uses JSON (no protobuf)
    ├── metadata.json                 # type: "ui_qml"
    ├── Main.qml                      # ← ENTIRE multiplayer logic in one file
    └── icons/tictactoe.png
```

---

## Part 1: Eight Research Questions Answered

---

### Q1 — Messaging Layer: What SDK/library handles P2P communication?

**Answer:** The built-in `delivery_module` — a pre-installed Logos Basecamp core module that wraps a Waku/libp2p node. It is accessed through the same IPC mechanism as any other module, NOT through Waku bindings directly.

**C++ init** (`tictactoe-ui-cpp/src/tictactoe_backend.cpp:65–128`):

```cpp
// #include "logos_api.h"
// #include "logos_api_client.h"

void TicTacToeBackend::enableMultiplayer()
{
    // Step 1 — get an IPC client handle for delivery_module
    m_deliveryClient = m_logosAPI->getClient("delivery_module");
    if (!m_deliveryClient) {
        qWarning() << "TicTacToeBackend: failed to get delivery_module client";
        return;
    }

    // Step 2 — configure and start the Waku node
    QString config = R"({"logLevel":"INFO","mode":"Core","preset":"logos.dev","relay":true})";
    m_deliveryClient->invokeRemoteMethod("delivery_module", "createNode", config);
    m_deliveryClient->invokeRemoteMethod("delivery_module", "start");

    // Step 3 — subscribe to a content topic
    m_deliveryClient->invokeRemoteMethod("delivery_module", "subscribe", m_contentTopic);

    // Step 4 — get a LogosObject handle for event subscription
    m_deliveryObject = m_deliveryClient->requestObject("delivery_module");
    m_deliveryClient->onEvent(m_deliveryObject, "messageReceived",
        [this](const QString& /*eventName*/, const QVariantList& data) {
            // ... handle incoming message ...
        });

    m_multiplayerEnabled = true;
}
```

**QML init** (`tictactoe-ui-qml/Main.qml:239–248`):

```qml
function enableMultiplayer() {
    var config = '{"logLevel":"INFO","mode":"Core","preset":"logos.dev","relay":true}'
    callDelivery("createNode", [config])
    callDelivery("start", [])
    callDelivery("subscribe", [root.contentTopic])
    // Register for host-bridged events:
    if (typeof logos !== "undefined" && logos.onModuleEvent)
        logos.onModuleEvent("delivery_module", "messageReceived")
    root.multiplayerEnabled = true
}

// Helper (line 180–184):
function callDelivery(method, args) {
    if (typeof logos === "undefined" || !logos.callModule) return -1
    return logos.callModule("delivery_module", method, args)
}
```

**delivery_module full API surface (confirmed from usage):**

| Method | Args | Returns | Purpose |
|--------|------|---------|---------|
| `createNode` | JSON config string | — | Initialise Waku node |
| `start` | — | — | Connect to network |
| `stop` | — | — | Disconnect |
| `subscribe` | topic string | — | Subscribe to content topic |
| `unsubscribe` | topic string | — | Unsubscribe |
| `send` | topic, base64-payload | — | Broadcast a message |

**Event:** `messageReceived`
- `data[0]` — content topic string
- `data[1]` — sender public key / peer ID
- `data[2]` — base64-encoded payload (delivery's own wrapping layer)

---

### Q2 — Message Schema: How are moves encoded/decoded?

**Answer:** Two parallel implementations exist in the same branch. The C++ UI uses **protobuf**; the QML UI uses **compact JSON**. Both are **double base64-encoded** because the delivery_module itself wraps payloads in base64.

#### Proto definition (`tictactoe-ui-cpp/proto/tictactoe.proto`)

```protobuf
syntax = "proto3";
package tictactoe;

message Move {
    uint32 row    = 1;
    uint32 col    = 2;
    uint32 player = 3;  // 1 = X, 2 = O
}

message GameMessage {
    oneof payload {
        Move move     = 1;
        bool new_game = 2;
    }
}
```

#### C++ encode + send (`tictactoe_backend.cpp:43–63`)

```cpp
void TicTacToeBackend::broadcastMove(int row, int col, int player)
{
    tictactoe::GameMessage msg;
    auto* move = msg.mutable_move();
    move->set_row(row);
    move->set_col(col);
    move->set_player(player);

    std::string serialized;
    msg.SerializeToString(&serialized);

    // Base64-encode protobuf bytes so they survive delivery module's
    // QString → UTF-8 → base64 pipeline without corruption.
    QString payload = QString::fromLatin1(
        QByteArray(serialized.data(), serialized.size()).toBase64());

    m_deliveryClient->invokeRemoteMethod(
        "delivery_module", "send", m_contentTopic, payload);
    m_messagesSent++;
    emit deliveryChanged();
}
```

#### C++ decode on receive (`tictactoe_backend.cpp:88–119`)

```cpp
[this](const QString& /*eventName*/, const QVariantList& data) {
    if (data.size() < 3) return;

    // data[2] is delivery module's base64 wrap around our base64 payload
    QByteArray deliveryPayload = QByteArray::fromBase64(data[2].toString().toUtf8());
    // Our base64 layer → raw protobuf bytes
    QByteArray protoBytes = QByteArray::fromBase64(deliveryPayload);

    tictactoe::GameMessage msg;
    if (!msg.ParseFromArray(protoBytes.data(), protoBytes.size())) {
        qWarning() << "failed to parse protobuf message";
        return;
    }

    if (msg.has_move()) {
        m_logos->tictactoe.play(msg.move().row(), msg.move().col());
        m_messagesReceived++;
        emit remoteMovePlayed();
    } else if (msg.has_new_game()) {
        m_logos->tictactoe.newGame();
        m_messagesReceived++;
        emit remoteMovePlayed();
    }
}
```

#### QML JSON encode + send (`Main.qml:261–275`)

```qml
function broadcastMove(row, col, player) {
    if (!root.multiplayerEnabled || !root.deliveryStarted) return
    var msg = JSON.stringify({"t": "m", "r": row, "c": col, "p": player})
    var payload = Qt.btoa(msg)      // our base64 layer
    callDelivery("send", [root.contentTopic, payload])
    root.messagesSent++
}

function broadcastNewGame() {
    if (!root.multiplayerEnabled || !root.deliveryStarted) return
    var msg = JSON.stringify({"t": "n"})
    var payload = Qt.btoa(msg)
    callDelivery("send", [root.contentTopic, payload])
    root.messagesSent++
}
```

#### QML JSON decode on receive (`Main.qml:277–296`)

```qml
function handleDeliveryMessage(data) {
    if (!root.multiplayerEnabled || data.length < 3) return
    try {
        // data[2] is delivery module's base64 → decode → our base64 → decode → JSON
        var deliveryPayload = Qt.atob(data[2])
        var jsonStr = Qt.atob(deliveryPayload)
        var msg = JSON.parse(jsonStr)

        if (msg.t === "m") {
            callModule("play", [msg.r, msg.c])
            root.messagesReceived++
            refreshBoard()
        } else if (msg.t === "n") {
            callModule("newGame", [])
            root.messagesReceived++
            refreshBoard()
        }
    } catch (e) {
        // Ignore unparseable messages (e.g. protobuf from C++ peer)
    }
}
```

**⚠️ Double base64 is mandatory.** Delivery module wraps in base64 internally. If you send raw bytes or single-encoded base64, the decode on the other side will be off by one layer.

---

### Q3 — Topic/Channel Structure: How is a game session identified?

**Answer:** A hardcoded content topic string per UI variant. No dynamic room IDs in the reference.

**C++ backend** (`tictactoe_backend.h:53`):
```cpp
QString m_contentTopic = "/tictactoe/1/moves/proto";
```

**QML** (`Main.qml:20`):
```qml
property string contentTopic: "/tictactoe/1/moves/json"
```

**Pattern:** `/<game-name>/<version>/<channel>/<encoding>`

The two UIs use different topic suffixes (`/proto` vs `/json`) so they don't accidentally cross-talk. The QML comment on line 294 explicitly acknowledges this:
```qml
// Ignore unparseable messages (e.g., protobuf from C++ UI)
```

**⚠️ No session isolation in the reference.** A hardcoded topic means every player running tictactoe on the Waku network affects every other player's board. For Scorched Earth, the topic must include a per-room ID.

---

### Q3b — Thread Safety: QMetaObject::invokeMethod (from logos-chat-ui)

**⚠️ Critical finding from `logos-chat-ui` (`ChatWindow.cpp:181–243`):** All `on()` event callbacks fire on the SDK's background thread. Any UI update or shared-state mutation **must** be marshalled to the main thread via `QMetaObject::invokeMethod` with `Qt::QueuedConnection`. The tictactoe reference omits this because its C++ UI does not subscribe to events. logos-chat-ui is the authoritative production pattern.

```cpp
// CORRECT (logos-chat-ui pattern for ALL events)
m_logos->chat_module.on("chatNewMessage",
    [this](const QVariantList& data) {
        QMetaObject::invokeMethod(
            this,
            [this, data]() { onChatNewMessage(data); },  // data by VALUE — mandatory
            Qt::QueuedConnection                          // posts to UI event loop
        );
    });
```

This applies identically to `m_deliveryClient->onEvent(...)` in Scorched Earth's C++ plugin.

**Also from chat-ui:** `setEventCallback()` must be called before `startChat()`. Equivalent for delivery_module is unknown — but subscribe before `start()` as a safe ordering.

---

### Q4 — Send/Receive Pattern: Exact signatures

**C++ send (invokeRemoteMethod):**
```cpp
// Single arg:
m_deliveryClient->invokeRemoteMethod("delivery_module", "start");
m_deliveryClient->invokeRemoteMethod("delivery_module", "subscribe", m_contentTopic);

// Two args (topic + payload):
m_deliveryClient->invokeRemoteMethod("delivery_module", "send", m_contentTopic, payload);
```

**C++ receive (event callback):**
```cpp
// requestObject returns a handle for event subscriptions
m_deliveryObject = m_deliveryClient->requestObject("delivery_module");

m_deliveryClient->onEvent(
    m_deliveryObject,
    "messageReceived",                              // event name
    [this](const QString& eventName,               // always "messageReceived"
           const QVariantList& data) {             // [topic, senderKey, base64payload]
        QByteArray outer = QByteArray::fromBase64(data[2].toString().toUtf8());
        QByteArray inner = QByteArray::fromBase64(outer);
        // parse inner as protobuf or JSON
    }
);
```

**QML send:**
```qml
logos.callModule("delivery_module", "send", [topic, base64payload])
```

**QML receive — two-step registration:**
```qml
// Step 1: tell the host which module events to forward to QML
logos.onModuleEvent("delivery_module", "messageReceived")

// Step 2: handle forwarded events
Connections {
    target: typeof logos !== "undefined" ? logos : null
    function onModuleEventReceived(moduleName, eventName, data) {
        if (moduleName === "delivery_module" && eventName === "messageReceived")
            handleDeliveryMessage(data)
    }
}
```

**data array layout (both C++ and QML):**
```
data[0]  →  content topic string
data[1]  →  sender public key / peer ID  (use this for self-echo filtering)
data[2]  →  base64-encoded payload (delivery's wrapping)
```

---

### Q5 — Turn Coordination: Whose turn is it?

**Answer:** Entirely client-side. No network-level enforcement. The C library enforces turn order locally via its state machine, but anyone can call `play()` at any time.

**Core module `tictactoe_plugin.cpp:39–47`:**
```cpp
int TicTacToePlugin::play(int row, int col)
{
    TicTacToeError err = tictactoe_play(m_game, row, col);
    if (err == TICTACTOE_OK) {
        TicTacToeStatus s = tictactoe_status(m_game);
        emit eventResponse("played",
            QVariantList() << row << col << static_cast<int>(s));
    }
    return static_cast<int>(err);   // returns TICTACTOE_ERR_GAME_OVER etc. if wrong turn
}
```

The C lib will reject a call from the wrong player (`TICTACTOE_ERR_CELL_OCCUPIED` if another player goes twice in a row since turns alternate), but:

1. There is **no cryptographic signing** of moves
2. Any remote peer can send any move
3. The delivery_module broadcasts to ALL subscribers — **including the sender** (self-echo)

**Self-echo** is the critical consequence: when you make a move locally AND broadcast it, you receive your own broadcast back and apply it a second time. The tictactoe QML code does not filter for this. For Scorched Earth this must be handled explicitly.

---

### Q6 — Session Lifecycle: How do players find each other?

**Answer:** No discovery mechanism. Both players independently click "Enable Multiplayer," which starts a Waku node and subscribes to the **same hardcoded topic**. The network topology handles peer discovery via the `logos.dev` preset.

**Full lifecycle (QML, `Main.qml:239–298`):**

```
1. Player clicks "Enable Multiplayer"
      ↓ createNode({"preset":"logos.dev","relay":true})
      ↓ start()             ← connects to logos.dev bootstrap nodes
      ↓ subscribe(topic)    ← subscribes to content topic
      ↓ logos.onModuleEvent("delivery_module", "messageReceived")

2. Any player makes a move
      ↓ callModule("tictactoe", "play", [row, col])     ← local
      ↓ broadcastMove(row, col, player)                 ← network

3. Remote message arrives
      ↓ onModuleEventReceived fires in QML
      ↓ handleDeliveryMessage(data)
      ↓ callModule("tictactoe", "play", [r, c])         ← apply remotely

4. Player clicks "Disable Multiplayer"
      ↓ unsubscribe(topic)
      ↓ stop()
```

**No GAME_START handshake.** No room ID exchange. No lobby. Whoever is subscribed to the same topic shares a game.

---

### Q7 — Module Integration: How does this plug into Logos Basecamp?

**Core module manifest** (`tictactoe/metadata.json`):
```json
{
  "name": "tictactoe",
  "version": "1.0.0",
  "type": "core",
  "category": "game",
  "description": "Tic-tac-toe module wrapping the libtictactoe C library",
  "main": "tictactoe_plugin",
  "dependencies": [],
  "nix": {
    "packages": { "build": [], "runtime": [] },
    "external_libraries": [],
    "cmake": {
      "extra_include_dirs": ["lib"],
      "extra_link_libraries": []
    }
  }
}
```

**QML UI manifest** (`tictactoe-ui-qml/metadata.json`):
```json
{
  "name": "tictactoe_ui_qml",
  "version": "1.0.0",
  "description": "Tic-tac-toe QML UI — QML frontend for tictactoe module",
  "type": "ui_qml",
  "main": "Main.qml",
  "dependencies": ["tictactoe"],
  "category": "games",
  "icon": "icons/tictactoe.png"
}
```

**⚠️ tictactoe-ui-qml uses the DEPRECATED 0.1.x manifest format.** Per `manifest-format.md` (verified 2026-04-13, status: active), the correct 0.2.0 format is `"view": "Main.qml"` + `"main": {}`. The tictactoe multiplayer branch still uses the old `"main": "Main.qml"` string format, which causes **silent load failure** in Basecamp 0.2.0. Scorched Earth MUST use the new format. See: `basecamp-skills/skills/manifest-format.md`.

**C++ plugin registration** (`tictactoe_plugin.h:10–14`):
```cpp
class TicTacToePlugin : public QObject, public TicTacToeInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID TicTacToeInterface_iid FILE "metadata.json")
    Q_INTERFACES(TicTacToeInterface PluginInterface)
```

Interface IID (`tictactoe_interface.h:53`):
```cpp
#define TicTacToeInterface_iid "org.logos.TicTacToeInterface"
Q_DECLARE_INTERFACE(TicTacToeInterface, TicTacToeInterface_iid)
```

**initLogos — critical rule** (`tictactoe_plugin.cpp:17`):
```cpp
// NOTE: NOT declared 'override' — called reflectively via QMetaObject::invokeMethod
void TicTacToePlugin::initLogos(LogosAPI* logosAPIInstance)
{
    logosAPI = logosAPIInstance;          // store in base class PUBLIC member
    if (logosAPI)
        logos = new LogosModules(logosAPI);
}
```

**Nix build** (`tictactoe/flake.nix`):
```nix
outputs = inputs@{ logos-module-builder, ... }:
  logos-module-builder.lib.mkLogosModule {
    src = ./.;
    configFile = ./metadata.json;
    flakeInputs = inputs;
  };
```

**CMake** (`tictactoe/CMakeLists.txt`):
```cmake
include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

add_library(tictactoe SHARED lib/libtictactoe.c)

logos_module(
    NAME tictactoe
    SOURCES
        src/tictactoe_interface.h
        src/tictactoe_plugin.h
        src/tictactoe_plugin.cpp
    LINK_TARGETS tictactoe
)
```

**CMake with protobuf** (`tictactoe-ui-cpp/CMakeLists.txt`):
```cmake
find_package(Protobuf REQUIRED)
set(PROTO_GEN_DIR ${CMAKE_CURRENT_BINARY_DIR}/proto_gen)

add_custom_command(
    OUTPUT ${PROTO_GEN_DIR}/tictactoe.pb.cc ${PROTO_GEN_DIR}/tictactoe.pb.h
    COMMAND protobuf::protoc
        --cpp_out=${PROTO_GEN_DIR}
        -I${PROTO_DIR}
        ${PROTO_DIR}/tictactoe.proto
    DEPENDS ${PROTO_DIR}/tictactoe.proto
)

logos_module(
    NAME tictactoe_ui_cpp
    SOURCES ... ${PROTO_SRC} ${PROTO_HDR}
    INCLUDE_DIRS ... ${PROTO_GEN_DIR}
)
target_link_libraries(tictactoe_ui_cpp_module_plugin PRIVATE
    Qt6::Widgets protobuf::libprotobuf)
```

Protobuf dependency declared in `tictactoe-ui-cpp/metadata.json`:
```json
"nix": {
    "packages": {
        "build": ["protobuf"],
        "runtime": ["protobuf"]
    }
}
```

**Install paths:**
```
~/.local/share/Logos/LogosBasecamp/modules/tictactoe/
    manifest.json  (or metadata.json — both used, verify which scanner reads)
    tictactoe_plugin.so
    libtictactoe.so

~/.local/share/Logos/LogosBasecamp/plugins/tictactoe_ui_qml/
    metadata.json
    Main.qml
    icons/tictactoe.png
```

---

### Q8 — QML vs JS Split: What lives where?

**Answer:** The QML UI (`tictactoe-ui-qml`) places **everything** inside a single `Main.qml` as inline JS functions. There are no separate `.js` module files.

| Component | Language | Owns |
|-----------|----------|------|
| `libtictactoe` | C | Pure game logic (no Qt) |
| `tictactoe_plugin` | C++ + Qt | Wraps C lib, exposes `Q_INVOKABLE` methods, emits `eventResponse` |
| `tictactoe_backend` (C++ UI) | C++ + Qt | Calls generated SDK, manages delivery_module lifecycle, encodes protobuf |
| `tictactoe_ui_plugin` (C++ UI) | C++ + Qt | Creates `QWidget`, wires signals/slots |
| `Main.qml` (QML UI) | QML + JS | **ALL** of: UI layout, game state properties, `logos.callModule()` calls, delivery_module lifecycle, JSON encode/decode, event handling |

**Key QML bridge functions** (all inline in Main.qml):

```qml
// Call the tictactoe core module
function callModule(method, args) {
    if (typeof logos === "undefined" || !logos.callModule) return -1
    return logos.callModule("tictactoe", method, args)
}

// Call the delivery_module (P2P transport)
function callDelivery(method, args) {
    if (typeof logos === "undefined" || !logos.callModule) return -1
    return logos.callModule("delivery_module", method, args)
}
```

**Waku/delivery code location in QML:**
- `enableMultiplayer()` — lines 239–249
- `disableMultiplayer()` — lines 251–259
- `broadcastMove()` — lines 261–267
- `broadcastNewGame()` — lines 269–275
- `handleDeliveryMessage()` — lines 277–296

**`logos` object API (confirmed from QML):**
```qml
logos.callModule(moduleName, methodName, argsArray)   // synchronous IPC, returns value
logos.onModuleEvent(moduleName, eventName)             // register for host-forwarded events
// fires Connections.onModuleEventReceived(moduleName, eventName, data)
```

---

## Part 2: Scorched Earth Architecture Design

### Core Design Decisions

1. **QML-only UI** — no C++ UI module, no protobuf. Uses JSON encoding same as `tictactoe-ui-qml`. Avoids the Nix protobuf build complexity entirely. Can add C++ + protobuf in v2.

2. **delivery_module for P2P** — same pattern as tictactoe multiplayer branch. Only the content topic and message schema change.

3. **Sync only inputs, not state** — only `SHOT` messages (angle + power + seq) are synced. Both clients run identical physics. `TURN_ACK` confirms result and advances turn.

4. **Room ID in topic** — `/scorched-earth/1/room-{roomId}/json` where `roomId` is a 6-char code displayed to both players. Fixes the "all players share one game" problem.

5. **Self-echo filtering** — compare `data[1]` (sender pubkey) to own pubkey. Need to discover how to get own pubkey from delivery_module. Fallback: sequence-number deduplication.

---

### Three Message Types (JSON encoding)

#### GAME_START
Broadcast by Player 1 (the room creator). Sets roles and optional wind.

```js
// Sent by creator:
{ "t": "gs", "room": "ab3x7q", "wind": 0, "role": 1 }
// role: 1 = this sender is Player 1 (fires first), receiver is Player 2

// Fields:
// t      string   "gs" — message type discriminator
// room   string   room ID (matches topic suffix)
// wind   number   wind force, 0 = no wind
// role   number   1 = sender is P1, 2 = sender is P2
```

#### SHOT
Broadcast by the active player when they fire.

```js
{ "t": "sh", "angle": 47.5, "power": 83.0, "seq": 1 }

// Fields:
// t      string   "sh"
// angle  number   degrees, 0.0–180.0 (0 = left, 90 = straight up, 180 = right)
// power  number   0.0–100.0
// seq    number   monotonic turn counter — used for ack matching + dedup
```

#### TURN_ACK
Broadcast by the receiving player after simulating the shot.

```js
{ "t": "ak", "seq": 1, "hit": true, "tank": 2 }

// Fields:
// t      string   "ak"
// seq    number   mirrors SHOT.seq
// hit    bool     true if projectile hit a tank
// tank   number   tank ID that was hit (1 or 2), 0 if terrain or miss
```

---

### File / Folder Structure

```
logos-module-scorched-earth/
│
├── README.md
├── .github/
│   └── workflows/build.yml              # same pattern as tictactoe
│
├── scorched-earth/                      # CORE MODULE
│   ├── metadata.json
│   ├── CMakeLists.txt
│   ├── flake.nix
│   └── src/
│       ├── game_interface.h             # Q_INVOKABLE abstract interface
│       ├── game_plugin.h                # Concrete plugin class
│       ├── game_plugin.cpp              # State management + eventResponse emit
│       ├── physics.h                    # Projectile math (pure C functions)
│       ├── physics.cpp
│       ├── terrain.h                    # Block grid (flat bool array)
│       └── terrain.cpp
│
└── scorched-earth-ui/                   # QML UI MODULE
    ├── metadata.json
    ├── Main.qml                         # Root: game state, delivery wiring, layout
    ├── icons/
    │   └── scorched-earth.png           # 28×28 RGBA PNG
    └── qml/
        ├── GameCanvas.qml               # Canvas: terrain, tanks, projectile animation
        ├── AimControl.qml               # Angle slider + power slider + Fire button
        ├── RoomPanel.qml                # Room code, Create/Join, Multiplayer toggle
        └── js/
            ├── physics.js               # Projectile simulation (mirrors C++ core)
            ├── delivery.js              # delivery_module send/receive helpers
            └── messages.js              # Message constructors + decoder
```

---

### QML Component Tree

```
Main.qml  (root Rectangle, color: "#1a1a1a")
│
│  // State properties
│  property int  myRole           // 1 = P1 (fires first), 2 = P2
│  property int  activePlayer     // whose turn: 1 or 2
│  property int  gamePhase        // 0=waiting, 1=aiming, 2=animating, 3=gameover
│  property var  terrain          // bool[cols*rows] — block alive/dead
│  property var  tanks            // [{x,y,hp}, {x,y,hp}]
│  property int  turnSeq          // monotonic shot counter
│  property string roomId         // 6-char room code
│  property string contentTopic   // "/scorched-earth/1/room-{roomId}/json"
│  property bool multiplayerOn
│
│  // Event bridge
│  Connections { target: logos; onModuleEventReceived: handleEvent() }
│
├── RoomPanel.qml
│   ├── Text           room code display ("Room: AB3X7Q")
│   ├── Button         "Create Room" → generate roomId, send GAME_START, subscribe
│   ├── Row
│   │   ├── TextField  enter room code to join
│   │   └── Button     "Join" → set roomId, subscribe, wait for GAME_START
│   └── Button         "Enable / Disable Multiplayer"
│
├── GameCanvas.qml
│   ├── Canvas         onPaint: drawTerrain() + drawTanks() + drawProjectile()
│   ├── Timer          animation tick: advances projectile, checks collision
│   └── Text           turn indicator ("Your turn" / "Waiting for opponent…")
│
└── AimControl.qml
    ├── Text           "Angle: 45°"
    ├── Slider         angle 0–180, enabled only when myTurn
    ├── Text           "Power: 80"
    ├── Slider         power 0–100, enabled only when myTurn
    └── Button         "Fire" → processShot() + broadcastShot()
                       disabled when gamePhase ≠ 1 (aiming)
```

---

### JS Modules

#### `qml/js/physics.js`

Deterministic projectile simulation. Must produce bit-identical results on both clients.
Use integer arithmetic for collision; floating-point only for trajectory drawing.

```js
// Constants
var GRAVITY = 0.3    // px/tick² — tune to feel right at chosen block size
var TICK_MS = 16     // ~60fps animation timer interval

// Compute full trajectory as array of {x, y} points
function trajectory(startX, startY, angleDeg, power) {
    var rad = angleDeg * Math.PI / 180
    var vx = Math.cos(rad) * power * 0.15
    var vy = -Math.sin(rad) * power * 0.15  // negative = upward in QML coords
    var pts = []
    var x = startX, y = startY
    for (var i = 0; i < 600; i++) {
        pts.push({x: Math.round(x), y: Math.round(y)})
        vy += GRAVITY
        x += vx; y += vy
        if (y > CANVAS_HEIGHT + 50) break  // fell off bottom
    }
    return pts
}

// Find first collision with terrain or tank
// Returns {type: "terrain"|"tank"|"oob", col, row, tankIdx}
function firstCollision(pts, terrain, tanks, cols, blockSize) {
    for (var i = 0; i < pts.length; i++) {
        var p = pts[i]
        // Out of bounds
        if (p.x < 0 || p.x >= cols * blockSize) return {type:"oob", i:i}
        // Terrain block
        var col = Math.floor(p.x / blockSize)
        var row = Math.floor(p.y / blockSize)
        if (row >= 0 && terrain[row * cols + col]) return {type:"terrain", col:col, row:row, i:i}
        // Tanks
        for (var t = 0; t < tanks.length; t++) {
            var tk = tanks[t]
            if (Math.abs(p.x - tk.x) < blockSize && Math.abs(p.y - tk.y) < blockSize)
                return {type:"tank", tankIdx:t, i:i}
        }
    }
    return {type:"miss", i:pts.length-1}
}
```

#### `qml/js/delivery.js`

```js
// Enable P2P transport and subscribe to topic
function enable(logos, topic) {
    var config = '{"logLevel":"INFO","mode":"Core","preset":"logos.dev","relay":true}'
    logos.callModule("delivery_module", "createNode", [config])
    logos.callModule("delivery_module", "start", [])
    logos.callModule("delivery_module", "subscribe", [topic])
    logos.onModuleEvent("delivery_module", "messageReceived")
}

function disable(logos, topic) {
    logos.callModule("delivery_module", "unsubscribe", [topic])
    logos.callModule("delivery_module", "stop", [])
}

// Send a JS object as double-base64 JSON
function send(logos, topic, msgObj) {
    var json = JSON.stringify(msgObj)
    var b64  = Qt.btoa(json)
    logos.callModule("delivery_module", "send", [topic, b64])
}

// Decode a messageReceived data array → JS object, or null on failure
function decode(data) {
    if (!data || data.length < 3) return null
    try {
        var outer = Qt.atob(data[2])   // delivery's wrapping
        var inner = Qt.atob(outer)     // our wrapping
        return JSON.parse(inner)
    } catch(e) { return null }
}

// Sender key for self-echo filtering
function senderKey(data) {
    return data.length >= 2 ? data[1] : ""
}
```

#### `qml/js/messages.js`

```js
function makeGameStart(roomId, wind, myRole) {
    return { t: "gs", room: roomId, wind: wind, role: myRole }
}

function makeShot(angle, power, seq) {
    return { t: "sh", angle: Math.round(angle * 10) / 10,
                      power: Math.round(power * 10) / 10,
                      seq: seq }
}

function makeTurnAck(seq, hitTank, tankId) {
    return { t: "ak", seq: seq, hit: hitTank, tank: tankId }
}

// Message type discriminator
var TYPE_GAME_START = "gs"
var TYPE_SHOT       = "sh"
var TYPE_TURN_ACK   = "ak"
```

---

### Core Module Interface (`scorched-earth/src/game_interface.h`)

```cpp
class ScorchedEarthInterface : public PluginInterface
{
public:
    virtual ~ScorchedEarthInterface() = default;

    // Session management
    Q_INVOKABLE virtual QString newGame(int cols, int rows, int windForce) = 0;
    // Returns: JSON {"terrain":[...bool], "tank1":{x,y}, "tank2":{x,y}}

    Q_INVOKABLE virtual QString getState() = 0;
    // Returns: same schema as newGame, plus {"status":0|1|2, "activePlayer":1|2}

    // Local tank movement (not synced — UI calls this on arrow key)
    Q_INVOKABLE virtual int moveTank(int tankId, int direction) = 0;
    // direction: -1=left, +1=right. Returns new x position.

    // Apply a shot and compute result (called for local AND remote shots)
    Q_INVOKABLE virtual QString processShot(int tankId, float angle, float power) = 0;
    // Returns: JSON {"hit":bool, "tankId":int, "removedBlocks":[[col,row],...], "seq":int}

    Q_INVOKABLE virtual int gameStatus() = 0;    // 0=ongoing, 1=p1wins, 2=p2wins
    Q_INVOKABLE virtual int activePlayer() = 0;  // 1 or 2

signals:
    void eventResponse(const QString& eventName, const QVariantList& data);
};

#define ScorchedEarthInterface_iid "org.logos.ScorchedEarthInterface"
Q_DECLARE_INTERFACE(ScorchedEarthInterface, ScorchedEarthInterface_iid)
```

---

### Metadata Files

**`scorched-earth/metadata.json`** (core module):
```json
{
  "name": "scorched_earth",
  "version": "0.1.0",
  "type": "core",
  "category": "game",
  "description": "Scorched Earth — turn-based artillery game",
  "main": "scorched_earth_plugin",
  "dependencies": [],
  "nix": {
    "packages": { "build": [], "runtime": [] },
    "external_libraries": [],
    "cmake": { "find_packages": [], "extra_sources": [], "extra_include_dirs": [], "extra_link_libraries": [] }
  }
}
```

**`scorched-earth-ui/metadata.json`** (QML UI) — using 0.2.0 format per `manifest-format.md`:
```json
{
  "name": "scorched_earth_ui",
  "version": "0.1.0",
  "type": "ui_qml",
  "view": "Main.qml",
  "main": {},
  "dependencies": ["scorched_earth"],
  "category": "games",
  "description": "Scorched Earth — 2-player multiplayer artillery",
  "icon": "icons/scorched-earth.png"
}
```

**⚠️ Do NOT use `"main": "Main.qml"` (old 0.1.x).** Basecamp 0.2.0 requires `"view"` for the QML entry point and `"main": {}` (empty object). Verified against embedded `counter_qml` manifest. Ref: `manifest-format.md`.

---

## Part 3: Implementation Risk Register

Ordered by severity. Each item is either a blocker or a known pitfall.

---

### 🔴 BLOCKER — Must resolve before writing any game code

**R1. `delivery_module` not present in target Basecamp AppImage**

The entire multiplayer layer depends on this module being pre-installed. The `platform-module-structure.md` installed-module inventory does NOT list `delivery_module`. The tictactoe multiplayer branch was added after that document was written.

*Test:* Open a fresh Basecamp AppImage, open the QML debugger or a probe plugin, call:
```qml
logos.callModule("delivery_module", "createNode", ['{"logLevel":"INFO","mode":"Core","preset":"logos.dev","relay":true}'])
```
If you get `{"error":"Invalid response"}` → delivery_module not installed. Game over until it is.

*Also check:* `ls ~/.local/share/Logos/LogosBasecamp/modules/` — look for a `delivery_module` directory.

---

**R2. `metadata.json` format — RESOLVED by skills, not a risk if followed correctly**

`manifest-format.md` (status: active, verified 2026-04-13) is definitive:

| Basecamp version | `main` key | `view` key | Result |
|-----------------|-----------|------------|--------|
| **0.2.0 (current)** | `{}` (empty object) | `"Main.qml"` | ✅ Loads |
| 0.1.x (deprecated) | `"Main.qml"` (string) | absent | ❌ Silent failure |

The tictactoe multiplayer branch `tictactoe-ui-qml/metadata.json` uses the OLD 0.1.x format. It would fail silently in Basecamp 0.2.0. Scorched Earth will use the 0.2.0 format.

**Verify anytime:** `cat /tmp/.mount_logos-*/usr/plugins/counter_qml/manifest.json` — this embedded plugin is always the ground truth for the current AppImage format.

---

### 🟡 IMPORTANT — Will cause bugs if not handled

**R3. Self-echo — own SHOT message received and applied twice**

The delivery_module broadcasts to ALL subscribers on a topic, including the sender. When you fire and send a `SHOT` message, you receive it back and will apply the shot a second time.

*Fix:* Filter by sender pubkey. On receive, check `data[1] === ownPubkey`. Need to confirm how to get own pubkey from delivery_module (no documented method yet — may be `getLocalPeerInfo()` or similar).

*Fallback:* Maintain a `Set` of sent sequence numbers. On receive, if `msg.seq` is in the set, skip it.

---

**R4. Physics determinism — JS `number` vs C++ `float`**

Both clients must compute identical collision results. JS `Math` uses IEEE 754 double (64-bit). If C++ core uses `float` (32-bit), results will diverge after a few ticks.

*Fix:* Keep projectile physics entirely in `physics.js` (QML side). Use integer math for terrain collision (block indices, not sub-pixel coordinates). The core module only needs to store/apply the result, not recompute it. `TURN_ACK` carries the canonical hit result — if the two clients diverge, ACK arbitrates.

---

**R5. `logos.callModule` blocks the UI thread ~20 seconds on timeout + re-entrancy**

Any call that fails or times out freezes the UI for ~20s. Worse: `callModule` blocks while pumping Qt's event loop — any running `Timer` fires re-entrantly *inside* the blocking call, building unbounded stack depth.

**Required pattern** (from `qml-patterns.md`, verified 2026-04-13):
```qml
property bool pollBusy: false

function poll() {
    if (root.pollBusy) return
    root.pollBusy = true
    // ... logos.callModule(...) calls ...
    root.pollBusy = false   // reset at EVERY return path
}
```

*Additional fix:* Wrap all delivery startup calls in a `Timer { singleShot: true; interval: 1 }` so they don't run synchronously from `Component.onCompleted`.

**R5b. `logos.callModule` returns double-JSON — must use `callModuleParse`**

From `qml-patterns.md` (verified 2026-04-13, issue xAlisher/keycard-basecamp#121): `logos.callModule()` wraps the C++ `QString` return in an extra JSON layer. Bare `JSON.parse()` yields a *string*, not an object.

**Add this helper to every QML file:**
```qml
function callModuleParse(raw) {
    try {
        var tmp = JSON.parse(raw)
        return (typeof tmp === 'string') ? JSON.parse(tmp) : tmp
    } catch (e) { return null }
}
// Usage:
var r = callModuleParse(logos.callModule("scorched_earth", "processShot", [tankId, angle, power]))
if (r && r.hit) { ... }
```

---

### 🟢 LOW RISK — Known, manageable

**R6. Protobuf tooling (not needed for v1)**

The QML JSON path avoids protobuf entirely. The C++ UI path needs `protoc` in Nix and `tictactoe.pb.h` generated at build time. Leave this for v2 if desired.

**R7. Room ID distribution — no in-band channel**

Players must share the 6-char room code out-of-band (voice, text, copy-paste). Display it prominently in the UI. This is acceptable for v1.

**R8. Multiple concurrent games on same topic**

If two pairs of players happen to generate the same 6-char room code, they would interfere. Probability is low (36^6 = 2.2B combinations), acceptable for v1.

**R9. Tank position sync after movement**

Tank movement (arrow keys, local only) is NOT synced. At game start, both clients must initialise tanks to the same deterministic positions derived from the room ID or `GAME_START` payload. Include initial tank X positions in the `GAME_START` message if needed.

**R10. Canvas repaint strategy**

QML `Canvas.onPaint` redraws the whole terrain every frame. At 800 blocks × 16fps during animation this is fine. If performance is an issue, switch to 800 `Rectangle` items (Qt scene graph GPU path) instead of raster canvas.

**R11. QML sandbox restrictions (from `qml-patterns.md`, verified 2026-04-13)**

All apply to Scorched Earth:
- No `Logos.Theme` / `Logos.Controls` — hardcode hex palette values
- No `QtGraphicalEffects` (ColorOverlay → blank screen)
- `QtQuick.Shapes` is unstable — avoid for terrain drawing; use `Canvas` or `Rectangle` items instead
- No `console.log` for debugging — use a visible `TextEdit` or `Text` element as print sink
- No file I/O from QML
- `Text` items are NOT selectable by default — use `TextEdit { readOnly: true }` for any selectable content
- `callModule` blocks ~20s on timeout and is re-entrant (see R5)

---

## Summary Table

| Question | Finding |
|----------|---------|
| P2P transport | `delivery_module` (Waku-wrapped IPC, pre-installed in Basecamp) |
| Message encoding | Protobuf (C++ UI) OR JSON (QML UI) — both double-base64 |
| Content topic | `/tictactoe/1/moves/json` — pattern: `/<name>/<ver>/<channel>/<enc>` |
| Topic per session | NOT in reference — must add `room-{id}` suffix for Scorched Earth |
| Send call | `logos.callModule("delivery_module","send",[topic,b64])` |
| Receive event | `logos.onModuleEvent()` + `Connections.onModuleEventReceived` |
| Turn enforcement | Client-side state machine only — no cryptographic validation |
| Session start | Toggle button — no lobby, no handshake, no GAME_START in reference |
| QML vs JS split | Single `Main.qml` with inline JS — no separate .js files in reference |
| Waku code location | Inside `Main.qml` JS functions |
| Proto file location | `tictactoe-ui-cpp/proto/tictactoe.proto` |
| Protobuf in QML | NOT used — QML uses JSON |
| Self-echo handled | ⚠️ NO — gap in reference implementation |
| Manifest format | ⚠️ Discrepancy between skills doc and tictactoe — test both |
