# Contributing

## Workflow (field-craft)

Specs-first, builder/verifier via GitHub issues.

### Before writing code

Open an issue: what, which epic (Part of #N), exit criteria.

### Branch naming

`feat/<issue-number>-short-description`

### PR rules

- Closes #N in description
- qmllint must pass (CI enforces)
- New C++ logic = new test in tst_game.cpp
- Manual checklist updated if UI changed

### No Sentry review

No existing users. Move fast.

## qmllint

```bash
find scorched-earth-ui -name "*.qml" | xargs qmllint
find scorched-earth-ui -name "*.qml" | xargs qmllint --json -   # agent-friendly
```

Install hook: `git config core.hooksPath .githooks`

## Headless tests

```bash
cd scorched-earth && nix build && ./result/bin/tst_game
```

## Skills

New pattern found → check basecamp-skills/ first → if game-specific, add to `docs/skills/`.
Include AppImage version in frontmatter. Reference in PR description.
