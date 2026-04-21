---
id: game-tank-fall-and-crush
title: "[game] Drop tanks on block destruction and crush if landing position is occupied"
tags: ["game"]
phase: integration
type: technique
severity: medium
severity_reason: Without fall logic tanks float in air; without crush check two tanks visually occupy the same cell
created: "2026-04-21"
last_used: "2026-04-21"
status: active
---

## Problem

When a terrain block is destroyed, any tank standing on it must fall.
If it falls onto the same column/row as the other tank, they visually overlap — need a crush kill.

## Recipe

After destroying a block in `processShot`, iterate over tanks:

```cpp
for (int i = 0; i < 2; ++i) {
    int tankCol      = tanks_[i].x / layout_.blockSize;
    int tankFloorRow = tanks_[i].y / layout_.blockSize;
    if (tankCol == destroyedCol && tankFloorRow == destroyedRow) {
        int newY = terrainFloorY(terrain_, tankCol, tanks_[i].y, layout_);

        if (newY >= layout_.rows * layout_.blockSize) {
            // Fell off the map
            tanks_[i].hp = 0;
            status_ = (i == 0) ? 2 : 1;
        } else {
            tanks_[i].y = newY;
            // Crush: if other tank already at same column and floor
            int other = 1 - i;
            if (tanks_[other].x / layout_.blockSize == tankCol &&
                tanks_[other].y == newY && status_ == 0) {
                tanks_[other].hp = 0;
                status_ = (other == 0) ? 2 : 1;
            }
        }
    }
}
```

## Why

`terrainFloorY` starts scanning from the destroyed row (now false), so it naturally
finds the next block below without special-casing. The crush check uses integer Y
equality which is guaranteed since both tank positions are always multiples of `blockSize`.
