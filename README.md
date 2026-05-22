# basecamp-scorched-earth

Turn-based artillery game for [Logos Basecamp](https://github.com/logos-co/logos-app).

**Status: proof-of-concept** — hot-seat and P2P multiplayer work end-to-end, but this is a dev demo, not a consumer release.

## What works

- Hot-seat (two players, one machine)
- P2P multiplayer over [Waku](https://waku.org) via `delivery_module` — no central server, no accounts
- Share a 6-character room code out of band to start a game

## POC limitations

- **Relies on `logos.dev` bootstrap fleet** — both peers must reach the Logos relay nodes for discovery. No self-hosted bootstrap option yet.
- **Random node key per launch** — new PeerID on every start; no persistent identity.
- **No internet independence** — both machines must be able to reach the `logos.dev` fleet. No self-hosted bootstrap option yet.
- **Single hardcoded terrain** — no procedural generation yet.
- **No persistence** — game state is in-memory; closing the app loses the session.
- **1v1 only** — no spectators or reconnect support.

## Cross-machine setup

```bash
# Wild (HOST, default port 60000)
~/logos-basecamp-current.AppImage

# Khidr (GUEST, port 60001 — avoids port conflict)
SCORCHED_TCP_PORT=60001 WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/1000 ~/logos-basecamp-current.AppImage
```

Both nodes get a random PeerID at startup and find each other via the `logos.dev` relay mesh. Share the 6-character room code out of band to start.

## Modules

- `scorched-earth/`     — C++ core plugin (game logic, physics, terrain)
- `scorched-earth-ui/`  — QML UI plugin (canvas rendering, turn management, multiplayer)

## Build

Requires Nix. Top-level `CMakeLists.txt` builds both modules.

## Skills

Project-local skills in `docs/skills/`. Complement — never duplicate — `basecamp-skills/`.

## Contributing

See `CONTRIBUTING.md` — specs-first, builder/verifier, qmllint enforced, no Sentry review.
