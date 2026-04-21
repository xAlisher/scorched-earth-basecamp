# Scorched Earth — Setup for a friend

Drop this file into Claude Code and say: **"set up Scorched Earth so I can play P2P"**

Claude Code will run all the commands below for you.

---

## What you need first

Ask your friend (the host) to send you two zip files:

- `scorched_earth_module.zip` — the game engine
- `scorched_earth_ui.zip` — the game UI
- `delivery_module.zip` — the P2P networking layer

Put them anywhere (e.g. `~/Downloads/`).

---

## Step 1 — Install Logos Basecamp

Download the AppImage from https://github.com/logos-co/logos-basecamp/releases
(pick the latest `logos-basecamp-*.AppImage` for Linux).

```bash
chmod +x ~/Downloads/logos-basecamp-*.AppImage
# Run it once to create data directories, then close it
~/Downloads/logos-basecamp-*.AppImage &
sleep 5 && pkill -f logos-basecamp
```

---

## Step 2 — Install the game files

```bash
# Adjust path if your zips are elsewhere
ZIPS=~/Downloads
BASE=~/.local/share/Logos/LogosBasecamp
mkdir -p $BASE

unzip -o "$ZIPS/scorched_earth_module.zip" -d $BASE/
unzip -o "$ZIPS/delivery_module.zip"       -d $BASE/
unzip -o "$ZIPS/scorched_earth_ui.zip"     -d $BASE/
```

---

## Step 3 — Launch and play

```bash
~/Downloads/logos-basecamp-*.AppImage &
```

1. Click **Scorched Earth** in the sidebar
2. Click **[ P2P ]** → **[ JOIN ]**
3. Enter the 6-letter room code your friend shares with you
4. Click **[ CONNECT ]**

The game starts automatically. You are **P2 (red)**. Your friend goes first.

---

## Troubleshooting

**Sidebar click does nothing** — the plugin failed to load. Run:
```bash
journalctl --user -n 30 --no-pager | grep -i "scorched\|failed"
```
and share the output.

**Game loads but P2P never connects** — `delivery_module` may not have started. Same command above, look for `delivery_module` errors.
