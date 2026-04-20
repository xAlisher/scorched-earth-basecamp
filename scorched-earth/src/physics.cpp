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
                         const std::vector<TankPos>& tanks)
{
    for (const auto& p : pts) {
        // Tank check (float coords, integer zone)
        for (int i = 0; i < (int)tanks.size(); ++i) {
            if (std::abs(p.x - tanks[i].x) < BLOCK_SIZE &&
                std::abs(p.y - tanks[i].y) < BLOCK_SIZE) {
                return {true, true, i, -1, -1, p};
            }
        }
        // Terrain check — integer grid lookup
        const int col = (int)(p.x / layout.blockSize);
        const int row = (int)(p.y / layout.blockSize);
        if (col >= 0 && col < layout.cols && row >= 0 && row < layout.rows) {
            if (terrain[row * layout.cols + col])
                return {true, false, -1, col, row, p};
        }
    }
    return {};
}
