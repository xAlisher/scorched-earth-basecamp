---
id: game-hit-zone-sizing
title: "[game] Size tank hit zones to the grid unit, not the visual sprite"
tags: ["game"]
phase: integration
type: technique
severity: medium
severity_reason: Pixel-perfect visual bounds make hits feel broken; grid-unit zones feel fair and are easier to reason about
created: "2026-04-21"
last_used: "2026-04-21"
status: active
---

## Problem

Using the exact visual sprite bounds (40×20 px for a 48×48 block world) as the hit zone
makes hits feel unreliable. A perfectly vertical return shot misses if the trajectory
origin is even a few pixels off from the hit zone edge.

## Recipe

Size the hit zone to the **grid unit** in X and to a playable height in Y:

```cpp
// Hit zone: full column width × 30px tall
if (p.x >= tanks[i].x           && p.x <= tanks[i].x + BLOCK_SIZE &&
    p.y >= tanks[i].y - 30      && p.y <= tanks[i].y)
    return hit;
```

- X: `[tank.x, tank.x + BLOCK_SIZE]` — exactly one column (48px). Any missile passing
  through the tank's column registers.
- Y: `[tank.y - 30, tank.y]` — slightly taller than visual body (20px) to account for
  discrete trajectory steps skipping over the body.

## Why

Trajectory points are computed at discrete steps (~7.5 px/step at power=50).
A 20px-tall hit zone can be skipped entirely if two consecutive trajectory points
straddle it. 30px reduces skip probability to near zero at normal power levels.
