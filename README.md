# basecamp-scorched-earth

> This is a personal, experimental hobby project. It is not an official Logos product. Not audited.


Turn-based artillery game for [Logos Basecamp](https://github.com/logos-co/logos-app).

**Status: proof-of-concept** — hot-seat and P2P multiplayer work end-to-end, but this is a dev demo, not a consumer release.

## What works

- Hot-seat (two players, one machine)
- P2P multiplayer over [Waku](https://waku.org) via `delivery_module` — no central server, no accounts
- Share a 6-character room code out of band to start a game

## POC limitations

- **Relies on logos.dev bootstrap fleet** — cross-machine peers find each other via the hardcoded `logos.dev` relay nodes, not direct dial. Static node hints in config are `127.0.0.1` — same-machine only.
- **Fixed node keys** — two hardcoded Waku node keys (`...1f20` / `...1f21`) produce deterministic PeerIDs. Only two simultaneous instances are supported without config changes.
- **No internet independence** — both machines must be able to reach the `logos.dev` fleet. No self-hosted bootstrap option yet.
- **Single hardcoded terrain** — no procedural generation yet.
- **No persistence** — game state is in-memory; closing the app loses the session.
- **1v1 only** — no spectators or reconnect support.

## Modules

- `scorched-earth/`     — C++ core plugin (game logic, physics, terrain)
- `scorched-earth-ui/`  — QML UI plugin (canvas rendering, turn management, multiplayer)

## Build

Requires Nix. Top-level `CMakeLists.txt` builds both modules.

## Skills

Project-local skills in `docs/skills/`. Complement — never duplicate — `basecamp-skills/`.

## Contributing

See `CONTRIBUTING.md` — specs-first, builder/verifier, qmllint enforced, no Sentry review.
