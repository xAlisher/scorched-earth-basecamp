# basecamp-scorched-earth

Turn-based artillery game for [Logos Basecamp](https://github.com/logos-co/logos-app).
Hot-seat single-player now. P2P multiplayer via Logos Messaging (xWaku) coming next.

**Status: experimental / dev-only** — pre-release Basecamp target. Not consumer-facing.

## Modules

- `scorched-earth/`     — C++ core plugin (game logic, physics, terrain)
- `scorched-earth-ui/`  — QML UI plugin (canvas rendering, turn management, multiplayer)

## Multiplayer (coming)

P2P via `delivery_module` (Logos Messaging / xWaku). No central server.
Share a 6-char room code out of band to start a game.

## Build

Requires Nix. Top-level `CMakeLists.txt` builds both modules.

## Skills

Project-local skills in `docs/skills/`. Complement — never duplicate — `basecamp-skills/`.

## Contributing

See `CONTRIBUTING.md` — specs-first, builder/verifier, qmllint enforced, no Sentry review.
