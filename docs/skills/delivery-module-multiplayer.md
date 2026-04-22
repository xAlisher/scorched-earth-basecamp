# delivery_module multiplayer — scorched-earth

_Scope: how to wire `delivery_module` v1.1.0 into the scorched-earth C++ core for P2P multiplayer._
_Source: tictactoe PR #5 (fryorcraken), Discord #logos-core-modules 2026-04-22._

---

## Required version

`logos-co/logos-delivery-module` **v1.1.0** (released 2026-04-22).

ABI break from 1.0.0: all API methods now return `LogosResult` instead of `bool`.
Regenerate `src/generated/delivery_module_api.h/.cpp` after updating the flake lock.

---

## Flake wiring

Add to `flake.nix` inputs:

```nix
logos-delivery-module.url = "github:logos-co/logos-delivery-module/1.1.0";
```

`mkLogosModule` does NOT auto-wire `follows` for delivery's sub-inputs (issue #83).
Add manually:

```nix
logos-delivery-module.inputs.logos-module-builder.follows = "logos-module-builder";
```

Add `"delivery_module"` to `metadata.json` dependencies.

---

## Node initialisation (C++ core)

Reference: `fryorcraken/logos-module-tictactoe` `tictactoe/src/tictactoe_plugin.cpp#L89`

```cpp
// 1. Create node — pass config JSON (fleet, content topic, ports)
QString result = m_delivery->createNode(R"({
    "fleet": "logos.dev",
    "contentTopic": "/scorched-earth/1/moves/proto",
    "tcpPort": 30305,
    "discv5UdpPort": 9010
})");

// 2. Start
m_delivery->start();

// 3. Subscribe
m_delivery->subscribe("/scorched-earth/1/moves/proto");
```

**Fleet:** use `logos.dev` — no RLN credentials required. Do NOT use TWN (requires RLN).

**Port-0 caveat:** `createNode` rejects `tcpPort: 0` (issue #24, fix in progress).
Until fixed: use explicit ports. Two instances on same machine need different ports.

---

## Sending moves

```cpp
// Serialise move to JSON, publish on content topic
QString moveJson = R"({"player":1,"angle":45,"power":80})";
m_delivery->publish("/scorched-earth/1/moves/proto", moveJson);
```

---

## Receiving moves

Subscribe to delivery events in `onEvent` / event callback:

```cpp
m_delivery->on("message", [this](const QVariantList& args) {
    // args[0] = content topic, args[1] = payload JSON
    QString payload = args.value(1).toString();
    handleRemoteMove(payload);
});
```

---

## LogosResult return handling

All delivery calls return `LogosResult` (JSON `{"ok":true}` / `{"ok":false,"error":"..."}`).
Parse before assuming success:

```cpp
auto r = LogosResult::fromJson(m_delivery->start());
if (!r.ok) {
    qWarning() << "delivery start failed:" << r.error;
}
```

---

## Logging caveat

`qDebug()` / `qWarning()` from the plugin are swallowed when running inside the Basecamp
AppImage (`logos_host.elf` child process — issue #163). Use file-based logging for
anything you need to see at runtime.

---

## Issue tracker

| Issue | Title | Status |
|-------|-------|--------|
| scorched-earth #38 | Move delivery integration from QML to C++ core | open |
| delivery-module #24 | `createNode` fails silently on port 0 | open, fix in progress |
| delivery-module #22 | Pre-`8c508d97` commits not buildable as downstream flake input | open |
| logos-module-builder #83 | `mkLogosModule` should auto-wire delivery follows | open |
| logos-basecamp #163 | Plugin stderr swallowed in AppImage | open |
