# logos-chat-ui — Messaging Implementation Exploration

**Source:** `https://github.com/logos-co/logos-chat-ui`
**Local clone:** `/home/alisher/logos-chat-ui`
**Date:** 2026-04-15
**Purpose:** Extract messaging patterns applicable to Scorched Earth multiplayer

---

## What This Repo Is

A C++ Qt **widget UI plugin** (`type: "ui"`) for `logos-chat-module` — a private Waku-based messaging module. This is a different transport than the `delivery_module` used by tictactoe's multiplayer branch, but the **SDK wiring patterns are identical** and directly applicable.

### Why it matters for Scorched Earth

- Demonstrates the **canonical production pattern** for `LogosModules` event subscriptions
- Shows the **thread-safety requirement** for event callbacks (QMetaObject::invokeMethod)
- Reveals `setEventCallback()` must be called before starting a module
- Shows how `chat_module.on("eventName", lambda)` works with real multi-event state machines
- UI component separation (panels, bubbles) is a reference for game UI structure

---

## File Structure

```
logos-chat-ui/
├── ChatUIComponent.h / .cpp     # Plugin entry point: createWidget(LogosAPI*)
├── metadata.json                # type: "ui" (C++ widget), depends: ["chat_module"]
├── interfaces/IComponent.h      # Same IComponent base as tictactoe-ui-cpp
├── src/
│   ├── ChatConfig.h             # Waku node config builder (env-driven)
│   ├── ChatWindow.h / .cpp      # QMainWindow — owns LogosModules*, wires all events
│   ├── ConversationListPanel    # Left panel QWidget
│   ├── ChatPanel                # Right panel QWidget — input + message scroll
│   └── MessageBubble            # Single message display widget
└── docs/spec.md                 # Full component specification
```

---

## Part 1: LogosModules / SDK Wiring

### Initialization — identical to tictactoe

```cpp
// ChatWindow.cpp:25–44
ChatWindow::ChatWindow(LogosAPI* logosAPI, QWidget* parent)
    : QMainWindow(parent), m_logosAPI(logosAPI)
{
    // Create LogosAPI ourselves if none provided (standalone app mode)
    if (!m_logosAPI) {
        m_logosAPI = new LogosAPI("core", this);
        m_ownsLogosAPI = true;
    }

    // Instantiate the generated SDK wrapper
    m_logos = new LogosModules(m_logosAPI);

    setupUI();
    setupMenu();
    setupEventHandlers();   // subscribe to events BEFORE calling initChat

    // Defer init to after the event loop starts
    QTimer::singleShot(0, this, [this]() { onInitChat(); });
}
```

**Key rule:** Use `QTimer::singleShot(0, ...)` to defer the first module call. Never call a module method synchronously in a constructor.

### Cleanup

```cpp
// ChatWindow.cpp:47–61
ChatWindow::~ChatWindow() {
    if (m_chatRunning && m_logos)
        m_logos->chat_module.stopChat();

    delete m_logos;
    m_logos = nullptr;

    if (m_ownsLogosAPI) {
        delete m_logosAPI;
    }
}
```

**Key rule:** Stop the module BEFORE deleting the SDK wrapper. Delete LogosAPI last, and only if you created it.

---

## Part 2: Event Subscription Pattern

### The canonical pattern — QMetaObject::invokeMethod with Qt::QueuedConnection

```cpp
// ChatWindow.cpp:173–246
void ChatWindow::setupEventHandlers() {
    if (!m_logos) return;

    m_logos->chat_module.on(
        "chatInitResult",
        [this](const QVariantList& data) {
            // Event fires on the SDK's background thread.
            // MUST marshal to the UI thread:
            QMetaObject::invokeMethod(
                this,
                [this, data]() { onChatInitResult(data); },
                Qt::QueuedConnection   // ← non-blocking, posts to UI event loop
            );
        });

    m_logos->chat_module.on(
        "chatNewMessage",
        [this](const QVariantList& data) {
            QMetaObject::invokeMethod(
                this,
                [this, data]() { onChatNewMessage(data); },
                Qt::QueuedConnection
            );
        });

    // ... same pattern for every event ...
}
```

**Why Qt::QueuedConnection is mandatory:**
- `m_logos->chat_module.on(...)` fires callbacks from a background Qt thread
- All UI updates must happen on the main thread
- `Qt::QueuedConnection` posts the lambda to the main thread's event queue
- `Qt::DirectConnection` (the default) would call back on the SDK thread → crash or corruption

**For Scorched Earth (C++ UI):** every `m_deliveryClient->onEvent(...)` callback must use the same pattern.

### setEventCallback — must precede start()

```cpp
// ChatWindow.cpp:465
m_logos->chat_module.setEventCallback();   // ← registers the event listener
bool success = m_logos->chat_module.startChat();
```

**⚠️ setEventCallback() must be called before startChat().** Without it, events fire but nobody receives them. Equivalent call for delivery_module: may not be needed (tictactoe didn't call it), but watch for missed events if `onEvent` is set up after `start()`.

---

## Part 3: chat_module API Surface

All methods return `bool` (success/failure). Results come via async events, not return values.

| Method | Args | Result Event |
|--------|------|-------------|
| `initChat(configJson)` | JSON string | `chatInitResult` |
| `startChat()` | — | `chatStartResult` |
| `stopChat()` | — | `chatStopResult` |
| `sendMessage(conversationId, contentHex)` | two QStrings | `chatSendMessageResult` |
| `newPrivateConversation(bundle, messageHex)` | two QStrings | `chatNewPrivateConversationResult` + `chatNewConversation` |
| `createIntroBundle()` | — | `chatCreateIntroBundleResult` |
| `getId()` | — | `chatGetIdResult` |
| `setEventCallback()` | — | (registers listener, no result event) |

### Init config schema (ChatConfig.h)

```cpp
// buildConfigJson() produces:
{
    "name":      "LogosUser_042",   // identity display name
    "port":      0,                  // 0 = random Waku port
    "clusterId": 2,                  // Waku cluster
    "shardId":   1,                  // Waku shard
    "staticPeer": "..."              // optional bootstrap peer multiaddr
}
```

---

## Part 4: Event Data Formats

All events fire `const QVariantList& data`. Common positions:

**Position convention across all events:**
```
data[0]  bool    success / primary payload
data[1]  int     return/error code (0 = success)
data[2]  QString result payload (JSON string or raw value)
data[3]  QString timestamp
```

### chatNewMessage (the most important)

```cpp
// ChatWindow.cpp:626–677
void ChatWindow::onChatNewMessage(const QVariantList& data) {
    QString jsonStr = data[0].toString();   // entire payload is JSON in data[0]
    QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
    QJsonObject obj = doc.object();

    QString conversationId = obj["conversationId"].toString();
    // Fallback key name:
    if (conversationId.isEmpty()) conversationId = obj["conversation_id"].toString();

    QString content = obj["content"].toString();
    // Decode hex if content is hex-encoded
    if (content.contains(QRegularExpression("^[0-9a-fA-F]+$")) && content.length() % 2 == 0)
        content = QString::fromUtf8(QByteArray::fromHex(content.toUtf8()));

    QString sender = obj["sender"].toString();
    if (sender.isEmpty()) sender = obj["from"].toString();
}
```

### chatNewConversation

```cpp
// ChatWindow.cpp:680–754
// data[0] = JSON string:
{
    "conversationId":   "abc123...",
    "conversationType": "private",
    "peerId":           "16Uiu2...",    // or "peerIdentity"
}
```

### chatInitResult / chatStartResult / chatStopResult

```cpp
bool success   = data[0].toBool();
int returnCode = data[1].toInt();    // 0 = success
QString msg    = data[2].toString(); // human-readable
// data[3] = timestamp string (ignored)
```

### chatGetIdResult

```cpp
QString identity = data[0].toString();   // peer identity string
// Used to display "ID: 16Uiu2..." in status bar
```

---

## Part 5: Message Content Encoding

Chat module requires **hex-encoded** content. Raw UTF-8 strings are sent as hex, decoded on receive.

**Send:**
```cpp
// ChatWindow.cpp:835
QString contentHex = QString::fromLatin1(content.toUtf8().toHex());
m_logos->chat_module.sendMessage(conversationId, contentHex);
```

**Receive:**
```cpp
// ChatWindow.cpp:646–649
if (content.contains(QRegularExpression("^[0-9a-fA-F]+$")) && content.length() % 2 == 0)
    content = QString::fromUtf8(QByteArray::fromHex(content.toUtf8()));
```

**For Scorched Earth + delivery_module:** Different encoding. delivery_module uses base64 (double-layer). Do NOT use hex encoding with delivery_module.

---

## Part 6: UI Component Architecture

### Widget hierarchy

```
ChatUIComponent::createWidget(LogosAPI*)
    └── new ChatWindow(logosAPI)            ← QMainWindow, owns everything
            ├── owns: LogosModules* m_logos
            ├── owns: QMap<conversationId, ConversationInfo> m_conversations
            ├── owns: QMap<conversationId, QList<MessageInfo>> m_messages
            ├── QSplitter (horizontal)
            │   ├── ConversationListPanel   ← QWidget, left 250px
            │   └── ChatPanel               ← QWidget, right (fills rest)
            │       └── MessageBubble[]     ← one per message (QWidget)
            └── QStatusBar
```

### ChatWindow owns all state

The window owns `m_conversations` and `m_messages` maps. Child panels have no state — they only receive data via slots and emit signals upward. This is the correct pattern for Basecamp widget plugins.

### MessageBubble — left/right alignment via spacer

```cpp
// MessageBubble.cpp:52–88
// My message: [spacer(1)] [bubble(1)]  — spacer pushes bubble right
// Their msg:  [bubble(1)] [spacer(1)]  — bubble on left, spacer fills right
if (m_isMe) {
    mainLayout->addWidget(spacer, 1);
    mainLayout->addWidget(bubbleContainer, 1);
} else {
    mainLayout->addWidget(bubbleContainer, 1);
    mainLayout->addWidget(spacer, 1);
}
```

Equal flex weights = each takes half the width. Simple and works.

---

## Part 7: Known Workarounds and Issues

### Issue #86 — newPrivateConversation doesn't return conversation ID

`chatNewPrivateConversationResult` doesn't reliably include the conversation ID. Workaround: store the pending initial message in `m_pendingInitialMessage` and attach it to the first `chatNewConversation` event that fires afterward.

```cpp
// ChatWindow.cpp:736–743
bool initiatedLocally = !m_pendingInitialMessage.isEmpty();
if (initiatedLocally) {
    m_messages[conversationId].append({"Me", m_pendingInitialMessage, createdAt, true});
    m_pendingInitialMessage.clear();
    shouldAutoSelect = true;
}
```

**Relevance for Scorched Earth:** delivery_module's `send()` is fire-and-forget with no result event. Don't expect a `sentResult` callback — just update local state immediately (optimistic update).

### Thread-safety mutex

```cpp
// ChatWindow.h:93
QMutex m_conversationsMutex;  // Protect conversation and message maps
```

Events can fire concurrently. Any shared state accessed from event callbacks needs a mutex. For Scorched Earth: `m_gameState` needs protection if delivery callbacks can fire while the game loop writes to it.

### QMetaObject::invokeMethod — captures data by value

```cpp
[this, data]() { onChatNewMessage(data); }
//      ^^^^ captured by value — critical
// If captured by reference, data would be destroyed before the queued call executes
```

Always capture `data` (QVariantList) by value in async lambdas.

---

## Part 8: Styling Reference

All hardcoded hex — no Logos.Theme. Consistent dark terminal palette:

| Element | Color |
|---------|-------|
| App/panel background | `#000000` / `#0A0A0A` |
| Panel divider/border | `#2a2a2a` |
| Primary text | `#FAFAFA` |
| Muted/timestamp text | `#4B5563` / `#6B7280` |
| Accent (buttons, my bubble) | `#10B981` |
| Hover accent | `#34D399` |
| Active/pressed accent | `#059669` |
| Peer message background | `#1F1F1F` |
| Unread badge | `#EF4444` |
| My bubble text | `#0A0A0A` (dark on green) |

Font: **JetBrains Mono** (monospace), 12pt body, 14pt headers, 10pt timestamps.

---

## Part 9: What Scorched Earth Takes From This

### Directly applicable patterns

| Pattern | Location | Use in Scorched Earth |
|---------|----------|-----------------------|
| `LogosModules* m_logos = new LogosModules(m_logosAPI)` | ChatWindow.cpp:38 | Identical — replace with delivery_module client |
| `m_logos->X.on("event", [this, data]() { ... })` | ChatWindow.cpp:181 | Same for `m_deliveryClient->onEvent(...)` |
| `QMetaObject::invokeMethod(Qt::QueuedConnection)` | ChatWindow.cpp:183 | **Mandatory** for all event callbacks |
| `QTimer::singleShot(0, this, init_lambda)` | ChatWindow.cpp:44 | Defer `createNode + start` to after event loop |
| Capture QVariantList data by value | everywhere | Mandatory for queued lambdas |
| Optimistic UI update, then confirm via event | onMessageSent:832 | Update game state immediately, confirm via TURN_ACK |
| Mutex for shared state | ChatWindow.h:93 | Protect game state struct from delivery thread |

### NOT applicable

| Pattern | Reason |
|---------|--------|
| `chat_module.initChat / startChat / stopChat` | Use `delivery_module.createNode / start / stop` |
| Hex encoding of message content | delivery_module uses base64, not hex |
| `setEventCallback()` | Not in delivery_module API (tictactoe didn't call it) |
| Conversation / bundle / peer identity system | Not applicable to game sessions |
| `chatNewConversation` / `chatNewMessage` event names | delivery_module uses `messageReceived` |

---

## Part 10: Concrete delivery_module Pattern for C++ UI

Based on chat-ui + tictactoe multiplayer branch combined:

```cpp
// DeliveryClient.h — helper wrapping delivery_module IPC

class DeliveryClient : public QObject {
    Q_OBJECT
public:
    explicit DeliveryClient(LogosAPI* api, const QString& topic, QObject* parent = nullptr)
        : QObject(parent)
        , m_client(api->getClient("delivery_module"))
        , m_topic(topic)
    {}

    void start() {
        if (!m_client) return;
        QString config = R"({"logLevel":"INFO","mode":"Core","preset":"logos.dev","relay":true})";
        m_client->invokeRemoteMethod("delivery_module", "createNode", config);
        m_client->invokeRemoteMethod("delivery_module", "start");
        m_client->invokeRemoteMethod("delivery_module", "subscribe", m_topic);

        m_object = m_client->requestObject("delivery_module");
        if (m_object) {
            m_client->onEvent(m_object, "messageReceived",
                [this](const QString&, const QVariantList& data) {
                    // Marshal to UI thread — MANDATORY
                    QMetaObject::invokeMethod(this,
                        [this, data]() { handleRawMessage(data); },
                        Qt::QueuedConnection);
                });
        }
    }

    void stop() {
        if (!m_client) return;
        m_client->invokeRemoteMethod("delivery_module", "unsubscribe", m_topic);
        m_client->invokeRemoteMethod("delivery_module", "stop");
    }

    void send(const QByteArray& protoBytes) {
        // Base64-encode our payload before delivery_module adds its own layer
        QString b64 = QString::fromLatin1(protoBytes.toBase64());
        m_client->invokeRemoteMethod("delivery_module", "send", m_topic, b64);
    }

signals:
    void messageReceived(const QString& senderKey, const QByteArray& payload);

private:
    void handleRawMessage(const QVariantList& data) {
        if (data.size() < 3) return;
        QString senderKey = data[1].toString();        // for self-echo filtering
        // Decode double-base64:
        QByteArray outer = QByteArray::fromBase64(data[2].toString().toUtf8());
        QByteArray inner = QByteArray::fromBase64(outer);
        emit messageReceived(senderKey, inner);         // emit to game logic
    }

    LogosAPIClient* m_client = nullptr;
    LogosObject*    m_object = nullptr;
    QString         m_topic;
};
```

**Usage in game plugin:**
```cpp
// In ScorchedEarthUiPlugin::createWidget(LogosAPI* api):
auto* delivery = new DeliveryClient(api, "/scorched-earth/1/room-AB3X7Q/proto");

// Self-echo filter:
connect(delivery, &DeliveryClient::messageReceived,
    [this, delivery](const QString& senderKey, const QByteArray& payload) {
        if (senderKey == m_ownPeerKey) return;   // skip own messages
        applyRemoteShot(payload);
    });

// Defer start:
QTimer::singleShot(0, delivery, &DeliveryClient::start);
```

---

## Appendix: chat_module vs delivery_module Comparison

| Aspect | chat_module | delivery_module |
|--------|------------|-----------------|
| Purpose | Private 1:1 messaging (bundles, conversations) | Generic pub/sub Waku relay |
| Init call | `initChat(configJson)` | `createNode(configJson)` |
| Start | `startChat()` | `start()` |
| Subscribe | automatic per conversation | explicit `subscribe(topic)` |
| Send | `sendMessage(conversationId, hexContent)` | `send(topic, base64payload)` |
| Receive event | `chatNewMessage` (JSON payload in data[0]) | `messageReceived` (data[0]=topic, data[1]=key, data[2]=b64payload) |
| Content encoding | hex UTF-8 | base64 (double-layer) |
| Identity/auth | intro bundles, peer IDs | sender pubkey in data[1] only |
| Session concept | named conversations | content topic string |
| setEventCallback | required before start | not observed as required |
| Used by | logos-chat-ui (private messaging) | tictactoe multiplayer |
| **Use for Scorched Earth** | ❌ wrong abstraction | ✅ pub/sub game messages |
