---
id: game-trajectory-origin
title: "[game] Fire trajectory from sprite body center, not column left edge"
tags: ["game"]
phase: integration
type: technique
severity: medium
severity_reason: Trajectory from column edge places a perfectly vertical shot outside the hit zone on return, making zero-angle self-hit impossible
created: "2026-04-21"
last_used: "2026-04-21"
status: active
---

## Problem

`tank.x` is the column left edge (always a multiple of BLOCK_SIZE). The tank body is
drawn offset (`x+4` to `x+44`). A vertical shot from `tank.x` returns to `tank.x`,
which is 4px outside the hit zone `[tank.x+4, tank.x+44]` — the shot can never self-hit.

## Recipe

In both C++ `processShot` and the QML arc computation, start from the horizontal center
of the tank body:

```cpp
// C++
float startX = tanks_[idx].x + 24;  // center of 40px body in 48px column
float startY = tanks_[idx].y;
```

```js
// QML arc
var px = tank.x + 24, py = tank.y
```

The `+24` is half the body width (40/2) plus the left offset (4): `4 + 40/2 = 24`.
For a 48px column this always lands within the column, so `startCol` is unchanged.

## Note

This offset also applies when the QML arc uses `leftStart` to terminate correctly
on the return path — the start cell is still `(tank.x/48, tank.y/48)`.
