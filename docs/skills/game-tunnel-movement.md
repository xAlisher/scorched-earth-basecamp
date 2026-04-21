---
id: game-tunnel-movement
title: "[game] Use terrainFloorY + ceiling check for tunnel traversal in block terrain"
tags: ["game"]
phase: integration
type: technique
severity: medium
severity_reason: terrainSnapY (topmost block) always snaps to cave ceilings, permanently blocking tunnel entry
created: "2026-04-21"
last_used: "2026-04-21"
status: active
---

## Problem

`terrainSnapY` scans from the top of a column and returns the first block found.
In a column with an overhanging ceiling (block at row 3) and a walkable floor (block at row 6),
`terrainSnapY` returns row 3 — the ceiling — making movement into the tunnel impossible.

## Recipe

Add `terrainFloorY` that scans **downward from the tank's current height**:

```cpp
int terrainFloorY(const std::vector<bool>& terrain, int col, int currentY,
                  const TerrainLayout& layout)
{
    int startRow = currentY / layout.blockSize;
    for (int row = startRow; row < layout.rows; ++row)
        if (terrain[row * layout.cols + col])
            return row * layout.blockSize;
    return layout.rows * layout.blockSize;  // no floor — falls off map
}
```

In `moveTank`, use a two-step strategy:

```cpp
// Step 1: try normal staircase (topmost surface, up to 1 block climb)
int snapY = terrainSnapY(terrain_, newCol, layout_);
if (snapY >= tanks_[idx].y - bs && canStand(snapY))
    → move to snapY

// Step 2: try tunnel entry (floor at current level, ceiling clearance required)
int floorY = terrainFloorY(terrain_, newCol, tanks_[idx].y, layout_);
if (canStand(floorY) && floorY >= tanks_[idx].y - bs)
    → move to floorY
```

`canStand(y)` checks that no block above the floor overlaps the tank body
(`blockBottom > y - TANK_H`):

```cpp
auto canStand = [&](int y) -> bool {
    int floorRow = y / layout_.blockSize;
    if (!terrain_[floorRow * layout_.cols + newCol]) return false;
    for (int r = 0; r < floorRow; ++r) {
        if (!terrain_[r * layout_.cols + newCol]) continue;
        if ((r + 1) * layout_.blockSize > y - TANK_H) return false;
    }
    return true;
};
```

## Terrain design constraint

For a tunnel to be physically passable: the ceiling row must be ≤ `floorRow - 2`.
With BLOCK_SIZE=48 and TANK_H=20: ceiling bottom at `(ceilRow+1)*48` must be ≤ `floorY - TANK_H`.
One empty row between ceiling and floor is sufficient clearance.
