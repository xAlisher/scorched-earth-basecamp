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
