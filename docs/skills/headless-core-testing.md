---
id: headless-core-testing
title: Headless C++ core testing with QtTest and JS/C++ determinism check
last_used: "2026-04-20"
created: "2026-04-20"
status: active
note: Direct QtTest approach (no logoscore daemon). For logoscore-based testing see basecamp-skills/logoscore-headless-testing.
---

## CMakeLists.txt test binary

```cmake
find_package(Qt6 REQUIRED COMPONENTS Core Test)

qt_add_executable(tst_game
    tests/tst_game.cpp
    src/physics.cpp
    src/terrain.cpp
    src/game_plugin.cpp
)
target_link_libraries(tst_game PRIVATE Qt6::Core Qt6::Test)
target_include_directories(tst_game PRIVATE src)
add_test(NAME tst_game COMMAND tst_game)
```

## Test file pattern

```cpp
#include <QtTest>
#include "physics.h"
class TestGame : public QObject {
    Q_OBJECT
private slots:
    void tst_trajectory_upward();
    void tst_terrain_hit();
};
QTEST_MAIN(TestGame)
#include "tst_game.moc"
```

## Determinism test — physics.js output must equal physics.cpp output

```bash
node tests/determinism.mjs > /tmp/js.json
./result/bin/determinism_cpp > /tmp/cpp.json
diff /tmp/js.json /tmp/cpp.json   # must be empty
```

Non-empty diff = clients will desync in multiplayer. Fix before merging.
