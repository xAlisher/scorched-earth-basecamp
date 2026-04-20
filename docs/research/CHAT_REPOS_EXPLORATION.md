# Chat Repos Exploration — Scorched Earth Reference

Ordered by priority: **prefer latest solutions**.

---

## 1. logos-chat-module (LATEST — liblogoschat C FFI)

**Path:** `/home/alisher/logos-chat-module`

This is the newest pattern. Wraps the `liblogoschat` shared library through a C FFI interface instead of using `waku_module` directly.

### Plugin Identity
```
IID: "org.logos.ChatModuleInterface"
metadata.json name: "chat_module"
```

### Startup Sequence
```
initLogos(logosAPI)           // creates LogosModules* logos
  → initChat(configJson)      // calls chat_new(cfg, init_callback, this)
  → setEventCallback()        // calls set_event_callback(chatCtx, event_callback, this)
  → startChat()               // calls chat_start(chatCtx, start_callback, this)
```

### C FFI API (liblogoschat.h)
```cpp
// All callbacks: typedef void (*Callback)(int callerRet, const char* msg, size_t len, void* userData)

void* chat_new(const char* config, Callback init_cb, void* userData);
void  chat_start(void* ctx, Callback start_cb, void* userData);
void  chat_stop(void* ctx, Callback stop_cb, void* userData);
void  chat_destroy(void* ctx);
void  set_event_callback(void* ctx, Callback event_cb, void* userData);

// Messaging
void  send_message(void* ctx, const char* convoId, const char* contentHex, Callback cb, void* userData);
void  new_private_conversation(void* ctx, const char* bundle, const char* contentHex, Callback cb, void* userData);
void  create_intro_bundle(void* ctx, Callback cb, void* userData);
void  get_id(void* ctx, Callback cb, void* userData);
```

### Static Callback Pattern
```cpp
static void init_callback(int callerRet, const char* msg, size_t len, void* userData) {
    ChatModulePlugin* self = static_cast<ChatModulePlugin*>(userData);
    // Always marshal to main thread:
    QMetaObject::invokeMethod(self, [self, callerRet, result]() {
        // handle result
    }, Qt::QueuedConnection);
}

static void event_callback(int callerRet, const char* msg, size_t len, void* userData) {
    ChatModulePlugin* self = static_cast<ChatModulePlugin*>(userData);
    QString jsonStr = QString::fromUtf8(msg, len);
    QJsonObject obj = QJsonDocument::fromJson(jsonStr.toUtf8()).object();
    QString eventType = obj["eventType"].toString();
    QMetaObject::invokeMethod(self, [self, eventType, obj]() {
        // Map eventType → emitEvent name
        if (eventType == "new_message")      self->emitEvent("chatNewMessage", ...);
        if (eventType == "new_conversation") self->emitEvent("chatNewConversation", ...);
        if (eventType == "delivery_ack")     self->emitEvent("chatDeliveryAck", ...);
    }, Qt::QueuedConnection);
}
```

### Full Event Table
| Event name (emitted) | data[] layout | Triggered by |
|---|---|---|
| `chatInitResult` | [bool ok, int code, QString msg, timestamp] | `init_callback` |
| `chatStartResult` | [bool ok, int code, QString msg, timestamp] | `start_callback` |
| `chatNewMessage` | [jsonStr, timestamp] | push from liblogoschat |
| `chatNewConversation` | [jsonStr, timestamp] | push from liblogoschat |
| `chatDeliveryAck` | [jsonStr, timestamp] | push from liblogoschat |

### Content Encoding
```cpp
// SEND — hex-encode the UTF-8 message content:
QString hexContent = message.toUtf8().toHex();
send_message(chatCtx, convoId.toUtf8(), hexContent.toUtf8(), send_cb, this);

// RECEIVE — hex-decode the content field in the JSON payload:
QByteArray decoded = QByteArray::fromHex(obj["content"].toString().toUtf8());
QString message = QString::fromUtf8(decoded);
```

### emitEvent Pattern
```cpp
void ChatModulePlugin::emitEvent(const QString& eventName, const QVariantList& data) {
    LogosAPIClient* client = logosAPI->getClient("chat_module");
    if (client) {
        client->onEventResponse(this, eventName, data);
    }
}
```

### metadata.json
```json
{
  "name": "chat_module",
  "type": "core",
  "main": "chat_module_plugin",
  "dependencies": [],
  "nix": {
    "external_libraries": [{"name": "chat", "build_command": "true"}],
    "cmake": {"extra_include_dirs": ["lib"]}
  }
}
```

### Scorched Earth Applicability
- **Not directly usable** for Scorched Earth — it's a private messaging layer (DMs + bundles), not pub/sub channels.
- **Key patterns to borrow**: static C callback pattern, `QMetaObject::invokeMethod(Qt::QueuedConnection)` for all callbacks, `emitEvent` via `getClient("module_name")->onEventResponse`, hex encoding.

---

## 2. logos-chat-legacy-ui (C++/QML Bridge Pattern)

**Path:** `/home/alisher/logos-chat-legacy-ui`

Shows the canonical pattern for exposing a C++ backend to QML as a named type.

### ChatBackend.h — Key Properties
```cpp
class ChatBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList messages READ messages NOTIFY messagesChanged)
    Q_PROPERTY(Status status READ status NOTIFY statusChanged)
    Q_ENUMS(Status)
public:
    enum Status { Disconnected, Connecting, Ready, Error };

    Q_INVOKABLE void joinChannel(const QString& channelName);
    Q_INVOKABLE void sendMessage(const QString& message);
    Q_INVOKABLE void clearMessages();
signals:
    void messagesChanged();
    void statusChanged();
};
```

### ChatBackend.cpp — Init and Event Handling
```cpp
// Init — deferred via QTimer (mandatory):
QTimer::singleShot(0, this, [this]() {
    m_logos->chat.initialize();
    m_logos->chat.joinChannel(m_channelName);
});

// Event subscription (NOTE: legacy code lacks QMetaObject::invokeMethod — add it in Scorched Earth):
m_logos->chat.on("chatMessage", [this](const QVariantList& data) {
    onChatMessage(data);
});

// onChatMessage — builds QVariantMap and appends:
void ChatBackend::onChatMessage(const QVariantList& data) {
    // data[0]=timestamp, data[1]=sender, data[2]=message
    QVariantMap msg;
    msg["timestamp"] = data[0];
    msg["sender"]    = data[1];
    msg["message"]   = data[2];
    msg["isSystem"]  = false;
    msg["isHistory"] = false;
    m_messages.append(msg);
    emit messagesChanged();
}
```

### ChatView.qml — QML Side
```qml
import ChatBackend 1.0   // C++ QObject registered as QML type

Item {
    ChatBackend {
        id: backend
    }

    ListView {
        id: messagesListView
        model: backend.messages
        // ...
        onCountChanged: Qt.callLater(function() {
            messagesListView.positionViewAtEnd()  // auto-scroll
        })
    }

    Button {
        onClicked: backend.sendMessage(inputField.text)
    }

    // Status check
    visible: backend.status === ChatBackend.Ready
}
```

### Scorched Earth Applicability
- **Borrow**: `Q_PROPERTY(QVariantList ...)` for game state, `Q_ENUMS` for game phase, `Q_INVOKABLE` for QML-callable methods.
- **Borrow**: `Qt.callLater(listView.positionViewAtEnd)` for any auto-scrolling list.
- **Fix**: Add `QMetaObject::invokeMethod(Qt::QueuedConnection)` around all event callbacks (the legacy code skips this — it's unsafe).
- **Scorched Earth game state** should be exposed as `Q_PROPERTY(QVariantMap gameState ...)` + `Q_PROPERTY(QVariantList terrain ...)`.

---

## 3. logos-chat-legacy-module (Direct waku_module API)

**Path:** `/home/alisher/logos-chat-legacy-module`

Uses `waku_module` directly — this is the lower layer that `delivery_module` also sits on top of. Critical reference for understanding the wire format.

### Key Constants
```cpp
const std::string DEFAULT_PUBSUB_TOPIC  = "/waku/2/rs/16/32";
const std::string CONTENT_TOPIC_PREFIX  = "/toy-chat/2/";
const std::string CONTENT_TOPIC_SUFFIX  = "/proto";
const std::string STORE_NODE = "...";  // bootstrap store peer
```
Content topic format: `/toy-chat/2/{channelName}/proto`

### Waku Init Config
```cpp
R"({
  "host": "0.0.0.0",
  "tcpPort": 60010,
  "clusterId": 16,
  "relay": true,
  "relayTopics": ["/waku/2/rs/16/32"],
  "shards": [1, 32, 64, 128, 256],
  "dnsDiscovery": true,
  "dnsDiscoveryUrl": "enrtree://..."
})"
```

### Init Sequence (waku_module)
```cpp
logos->waku_module.initWaku(configStr);
logos->waku_module.on("wakuMessage", [](const QVariantList& data) { /* handle */ });
logos->waku_module.setEventCallback();
logos->waku_module.startWaku();
```

### Subscribe to Channel
```cpp
std::string contentTopic = "/toy-chat/2/" + channelName + "/proto";
logos->waku_module.filterSubscribe(relayTopic, "[\"" + contentTopic + "\"]");
```

### Send Message (relayPublish)
```cpp
// 1. Build protobuf payload
ChatMessage chatMsg(username, message);
std::vector<uint8_t> serialized = chatMsg.serialize();  // hand-written proto wire format

// 2. Base64-encode
std::string base64Payload = base64Encode(serialized);

// 3. Build message JSON
uint64_t timestampNs = getCurrentTimestampProto();
std::string messageJson = R"({"payload":")" + base64Payload +
    R"(","contentTopic":")" + contentTopic +
    R"(","version":1,"timestamp":)" + std::to_string(timestampNs) +
    R"(,"ephemeral":false})";

// 4. Publish
logos->waku_module.relayPublish(DEFAULT_PUBSUB_TOPIC, messageJson);
```

### Receive Message (wakuMessage event)
```cpp
// data layout from wakuMessage event:
// data[0] = pubsubTopic (string)
// data[1] = messageHash (string) — use for dedup
// data[2] = payload (base64-encoded protobuf bytes)
// data[3] = contentTopic (string)
// data[4] = timestamp (uint64 as string)

logos->waku_module.on("wakuMessage", [](const QVariantList& data) {
    QString hash = data[1].toString();
    if (processedMessageHashes.count(hash.toStdString())) return;  // dedup
    processedMessageHashes.insert(hash.toStdString());

    std::vector<uint8_t> bytes = base64Decode(data[2].toString().toStdString());
    ChatMessage msg;
    if (!msg.deserialize(bytes)) return;
    // msg.formattedTimestamp(), msg.nick(), msg.message()
});
```

### Deduplication
```cpp
static std::unordered_set<std::string> processedMessageHashes;
// Key: data[1] (messageHash from Waku event)
```

### Store Query (History)
```cpp
std::string queryJson = R"({"contentTopics":[")" + contentTopic + R"("],"peerAddr":")" + STORE_NODE + R"("})";
logos->waku_module.storeQuery(queryJson, STORE_NODE);
// Results arrive as "historyMessage" events with same data[] layout
```

### Protobuf Schema (Chat2Message)
```protobuf
syntax = "proto3";
package chat;
message Chat2Message {
  uint64 timestamp = 1;
  string nick = 2;
  bytes  payload = 3;
}
```

### emitEvent Pattern (Legacy)
```cpp
void ChatPlugin::emitEvent(const QString& eventName, const QVariantList& data) {
    LogosAPIClient* client = logosAPI->getClient("chat");  // plugin name = "chat"
    if (client) client->onEventResponse(this, eventName, data);
}
// Events: "chatMessage" (live), "historyMessage" (store results)
```

### Scorched Earth Applicability
- **Not the preferred path** for Scorched Earth — use `delivery_module` instead.
- **Key reference**: wire format (base64 + JSON wrapper), `relayPublish` JSON schema, content topic naming.
- **Scorched Earth content topic**: `/scorched-earth/1/room-{roomId}/json`
- Deduplication pattern (`messageHash` unordered_set) is directly applicable.

---

## 4. logos-chat-tui (Rust — C API Surface Reference)

**Path:** `/home/alisher/logos-chat-tui`

A Rust terminal UI client for the `chat` plugin (logos-chat-legacy-module). Useful as a reference for the exact plugin API surface.

### Plugin API Called (via logos-rust-sdk)
```rust
// Load plugins in order:
logos.load_plugin("capability_module");
logos.load_plugin("waku_module");
logos.load_plugin("chat");  // ← plugin name is "chat"

let chat = logos.plugin("chat");

// Event subscriptions:
let chat_message_rx    = chat.on("chatMessage").unwrap();
let history_message_rx = chat.on("historyMessage").unwrap();

// Method calls:
chat.call("initialize", &[]);
chat.call("joinChannel", &[channel]);
chat.call("retrieveHistory", &[channel]);
chat.call("sendMessage", &[channel, username, message]);
```

### Event Data Layout
```rust
// EventData.get_str(index):
// [0] = timestamp string
// [1] = sender/nick string
// [2] = message content string
```

### Scorched Earth Applicability
- Confirms that `"chat"` plugin name (legacy) takes `sendMessage(channel, username, message)`.
- For Scorched Earth: use `delivery_module` plugin, not `waku_module` or `chat` directly.
- `logos.process_events()` in Rust = Qt event loop in C++ — events are polled, not pushed.

---

## 5. logos-chat-ui (QML — delivery_module Pattern)

**Path:** `/home/alisher/logos-chat-ui`

(Explored in prior session — see `CHAT_UI_EXPLORATION.md` for full details.)

### Key Patterns for Scorched Earth
```qml
// 1. LogosModules init:
property var logos: LogosModules { logosAPI: logosAPI }

// 2. Event subscription (delivery_module):
logos.onModuleEvent("delivery_module", "messageReceived")
Connections {
    target: logos
    function onModuleEventReceived(module, event, data) {
        if (module !== "delivery_module") return;
        // data[0] = contentTopic
        // data[1] = senderPubkey  ← filter self-echo here
        // data[2] = base64(base64(payload))
        var inner = Qt.atob(Qt.atob(data[2]));  // double decode
        var msg = JSON.parse(inner);
    }
}

// 3. Send via delivery_module:
logos.callModule("delivery_module", "send", [contentTopic, Qt.btoa(JSON.stringify(payload))])

// 4. Subscribe:
logos.callModule("delivery_module", "subscribe", [contentTopic])
```

---

## Decision Matrix for Scorched Earth

| Concern | Preferred Solution | Source |
|---|---|---|
| P2P message transport | `delivery_module` (`subscribe` + `send`) | logos-chat-ui, tictactoe |
| Double base64 decode | `Qt.atob(Qt.atob(data[2]))` | logos-chat-ui |
| Self-echo filter | Check `data[1] !== myPubkey` | tictactoe gap — add this |
| Thread safety in callbacks | `QMetaObject::invokeMethod(Qt::QueuedConnection)` | logos-chat-ui, logos-chat-module |
| First module call defer | `QTimer::singleShot(0, ...)` | tictactoe, basecamp-skills |
| C++/QML bridge | `Q_PROPERTY` + `Q_INVOKABLE` + `Q_ENUMS` | logos-chat-legacy-ui |
| Game state in QML | `Q_PROPERTY(QVariantMap gameState ...)` | logos-chat-legacy-ui pattern |
| Auto-scroll any list | `Qt.callLater(list.positionViewAtEnd)` | logos-chat-legacy-ui |
| Message dedup | `unordered_set<string> processedHashes` keyed on `data[1]` hash | logos-chat-legacy-module |
| Content topic naming | `/scorched-earth/1/room-{id}/json` | logos-chat-legacy-module pattern |
| callModule result unwrap | `callModuleParse` helper (double JSON) | basecamp-skills/qml-patterns.md |
| Re-entrancy guard | `pollBusy` flag | basecamp-skills/qml-patterns.md |
| Plugin emitEvent | `logosAPI->getClient(pluginName)->onEventResponse(this, name, data)` | logos-chat-module, logos-chat-legacy-module |
| Manifest format | `"view":"Main.qml"` + `"main":{}` (0.2.0) | basecamp-skills/manifest-format.md |

---

## Scorched Earth Message Protocol

Content topic: `/scorched-earth/1/room-{roomId}/json`

```json
// GAME_START
{ "type": "GAME_START", "roomId": "...", "players": ["pubkey1", "pubkey2"], "seed": 12345 }

// SHOT
{ "type": "SHOT", "player": "pubkey1", "angle": 45.0, "power": 75, "turn": 3 }

// TURN_ACK
{ "type": "TURN_ACK", "player": "pubkey2", "turn": 3 }
```

Payload goes through: `JSON.stringify(msg)` → `Qt.btoa(...)` → `delivery_module.send`

Receive: `Qt.atob(Qt.atob(data[2]))` → `JSON.parse(...)` → check `data[1] !== myPubkey`
