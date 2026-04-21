#include "physics.h"
#include <cmath>

std::vector<PhysPoint> trajectory(float startX, float startY,
                                  float angleDeg, float power)
{
    std::vector<PhysPoint> pts;
    const float rad = angleDeg * M_PI / 180.0f;
    float vx = std::cos(rad) * power * 0.15f;
    float vy = -std::sin(rad) * power * 0.15f;
    float x  = startX;
    float y  = startY;

    while (x >= 0 && x < CANVAS_WIDTH && y < CANVAS_HEIGHT) {
        pts.push_back({x, y});
        x  += vx;
        y  += vy;
        vy += GRAVITY;
    }
    return pts;
}

Collision firstCollision(const std::vector<PhysPoint>& pts,
                         const std::vector<bool>& terrain,
                         const TerrainLayout& layout,
                         const std::vector<TankPos>& tanks,
                         int shooterIdx)
{
    if (pts.empty()) return {};

    const int startCol = (int)(pts[0].x / layout.blockSize);
    const int startRow = (int)(pts[0].y / layout.blockSize);

    bool leftStart  = false;   // true once the missile has left the starting cell
    bool descending = false;   // true once the missile starts moving downward
    float prevY     = pts[0].y;

    for (const auto& p : pts) {
        const int col = (int)(p.x / layout.blockSize);
        const int row = (int)(p.y / layout.blockSize);

        // Skip the starting cell on the first pass only
        if (!leftStart) {
            if (col == startCol && row == startRow) { prevY = p.y; continue; }
            leftStart = true;
        }

        // Detect apex — once y increases the missile is descending (screen-Y down = larger)
        if (!descending && p.y > prevY) descending = true;
        prevY = p.y;

        // Tank hit zone: full column width (48px) × 30px tall.
        // Wider than the visual body (40×20) for playable precision.
        // Self-hit (shooter) is only allowed after the missile starts descending.
        for (int i = 0; i < (int)tanks.size(); ++i) {
            if (i == shooterIdx && !descending) continue;
            if (p.x >= tanks[i].x      && p.x <= tanks[i].x + BLOCK_SIZE &&
                p.y >= tanks[i].y - 30 && p.y <= tanks[i].y) {
                return {true, true, i, -1, -1, p};
            }
        }
        // Terrain check
        if (col >= 0 && col < layout.cols && row >= 0 && row < layout.rows) {
            if (terrain[row * layout.cols + col])
                return {true, false, -1, col, row, p};
        }
    }
    return {};
}
