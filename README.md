# basecamp-scorched-earth

Turn-based artillery game for [Logos Basecamp](https://github.com/logos-co/logos-app).

**Status: proof-of-concept** — hot-seat and P2P multiplayer work end-to-end, but this is a dev demo, not a consumer release.

## What works

- Hot-seat (two players, one machine)
- P2P multiplayer over [Waku](https://waku.org) via `delivery_module` — no central server, no accounts
- Share a 6-character room code out of band to start a game

## POC limitations

- **Requires `SCORCHED_PEER_IP` for cross-machine** — set to the other machine's IP for direct dial; defaults to `127.0.0.1` (same-machine only). Falls back to `logos.dev` relay if unset.
- **Fixed node keys** — two hardcoded Waku node keys (`...1f20` / `...1f21`) produce deterministic PeerIDs. Only two simultaneous instances are supported without config changes.
- **No internet independence** — both machines must be able to reach the `logos.dev` fleet. No self-hosted bootstrap option yet.
- **Single hardcoded terrain** — no procedural generation yet.
- **No persistence** — game state is in-memory; closing the app loses the session.
- **1v1 only** — no spectators or reconnect support.

## Cross-machine setup

Each machine sets `SCORCHED_PEER_IP` to the **other** machine's IP:

```bash
# Wild (HOST, default port 60000) — point at Khidr
SCORCHED_PEER_IP=<khidr-ip> ~/logos-basecamp-current.AppImage

# Khidr (GUEST, port 60001) — point at Wild
SCORCHED_TCP_PORT=60001 SCORCHED_PEER_IP=<wild-ip> WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 ~/logos-basecamp-current.AppImage
```

Omit `SCORCHED_PEER_IP` for same-machine two-instance testing (defaults to `127.0.0.1`).

## Modules

- `scorched-earth/`     — C++ core plugin (game logic, physics, terrain)
- `scorched-earth-ui/`  — QML UI plugin (canvas rendering, turn management, multiplayer)

## Build

Requires Nix. Top-level `CMakeLists.txt` builds both modules.

## Skills

Project-local skills in `docs/skills/`. Complement — never duplicate — `basecamp-skills/`.

## Contributing

See `CONTRIBUTING.md` — specs-first, builder/verifier, qmllint enforced, no Sentry review.
