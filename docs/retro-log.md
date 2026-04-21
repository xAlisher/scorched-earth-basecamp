# Retro Log

## win 2026-04-21
logos-module-builder migration complete: both scorched-earth (core C++) and scorched-earth-ui (QML) migrated to mkLogosModule / mkLogosQmlModule. Senty LGTM on first pass (issue #37). Merged to main.

## fail 2026-04-21
Q_PLUGIN_METADATA FILE wrong name: `FILE "plugin_metadata.json"` in game_plugin.h caused nix build failure ("Plugin Metadata file does not exist"). logos_module() CMake macro copies `metadata.json` (not plugin_metadata.json) to build dir for moc. Fix: rename reference to `FILE "metadata.json"` and delete plugin_metadata.json.

## fail 2026-04-21
mkLogosQmlModule single-file bundling: `"view": "Main.qml"` at project root made builder copy only Main.qml — omitting AimControl.qml, GameCanvas.qml, RoomPanel.qml. Plugin installed and icon appeared but click did nothing (silent). Fix: move all QML to qml/ subdir, set `"view": "qml/Main.qml"`.

## fail 2026-04-21
lgpm variant for ui_qml: lgpm install set variant to linux-amd64-dev for the ui_qml plugin. Basecamp UI loader expects linux-amd64. Module didn't load. Fix: echo -n "linux-amd64" > plugins/scorched_earth_ui/variant after every lgpm install.
