---
id: game-projectile-self-hit
title: "[game] Allow self-hit only after projectile passes apex (leftStart + descending flags)"
tags: ["game"]
phase: integration
type: technique
severity: medium
severity_reason: Without the descending guard, self-hits fire immediately on launch; without leftStart, return-arc self-hits never register
created: "2026-04-21"
last_used: "2026-04-21"
status: active
---

## Problem

A projectile fired straight up should be able to return and hit the shooter.
Two bugs prevent this:

1. Permanent `shooterIdx` exclusion — shooter can never be hit, even on return.
2. Permanent starting-cell skip — when missile returns to the same grid cell it fired from,
   the terrain check is also skipped, so the missile passes through the floor block.

## Recipe

Replace the permanent starting-cell skip and permanent shooter exclusion with two flags:

```cpp
bool leftStart  = false;  // true once missile has left the starting cell (first time only)
bool descending = false;  // true once missile starts moving downward (past apex)
float prevY     = pts[0].y;

for (const auto& p : pts) {
    const int col = (int)(p.x / layout.blockSize);
    const int row = (int)(p.y / layout.blockSize);

    // Skip starting cell on FIRST encounter only
    if (!leftStart) {
        if (col == startCol && row == startRow) { prevY = p.y; continue; }
        leftStart = true;
    }

    // Detect apex: screen-Y increases when falling
    if (!descending && p.y > prevY) descending = true;
    prevY = p.y;

    // Shooter excluded while ascending; allowed once descending
    for (int i = 0; i < (int)tanks.size(); ++i) {
        if (i == shooterIdx && !descending) continue;
        if (/* hit zone check */) return hit;
    }
    // Terrain check (also runs on return to starting cell once leftStart=true)
    ...
}
```

## Why

- `leftStart` ensures the starting cell is skipped only on departure, not on return.
- `descending` ensures the shooter can't immediately self-hit on the way up, but
  a zero-angle shot that goes up and comes back will correctly register as a self-hit.

## Note

Also fire the trajectory from the **horizontal center** of the tank body (`tank.x + 24`
for a 48px column / 40px body), not the column left edge. A perfectly vertical shot
from the left edge lands outside the hit zone on return.
