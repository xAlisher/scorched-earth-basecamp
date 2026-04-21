#pragma once

#include <vector>
#include "terrain.h"

// CRITICAL: constants must be identical to physics.js in the QML module.
// Determinism test (issue #31) verifies this.
static constexpr float GRAVITY      = 0.3f;
static constexpr int   BLOCK_SIZE   = 48;
static constexpr int   CANVAS_WIDTH = 960;
static constexpr int   CANVAS_HEIGHT= 480;

struct PhysPoint {
    float x, y;
};

struct TankPos {
    int x, y;
};

struct Collision {
    bool hit       = false;
    bool isTank    = false;
    int  tankId    = -1;   // 0-based index if isTank
    int  blockCol  = -1;
    int  blockRow  = -1;
    PhysPoint point{0, 0};
};

// Returns full trajectory until out-of-bounds.
// vx = cos(rad)*power*0.15, vy = -sin(rad)*power*0.15, GRAVITY per tick.
std::vector<PhysPoint> trajectory(float startX, float startY,
                                  float angleDeg, float power);

// Walk pts until a collision with terrain or tank.
// Integer arithmetic for grid lookup, float coords for path.
// Tank hit zone: abs(px-tankX) < BLOCK_SIZE && abs(py-tankY) < BLOCK_SIZE
// shooterIdx: 0-based index of the firing tank — excluded from hit detection
Collision firstCollision(const std::vector<PhysPoint>& pts,
                         const std::vector<bool>& terrain,
                         const TerrainLayout& layout,
                         const std::vector<TankPos>& tanks,
                         int shooterIdx = -1);
