#include "terrain.h"

std::vector<bool> buildHardcodedTerrain()
{
    // 20 cols × 10 rows, row-major (row*cols + col)
    // Row 0 = top. true = alive block.
    const int cols = 20;
    const int rows = 10;
    std::vector<bool> t(cols * rows, false);

    auto set = [&](int row, int col) { t[row * cols + col] = true; };

    // Row 2
    set(2, 4); set(2, 5); set(2, 12); set(2, 13);
    // Row 3
    set(3, 2); set(3, 3); set(3, 4); set(3, 5);
    set(3, 12); set(3, 13); set(3, 14); set(3, 15);
    // Row 4
    set(4, 1); set(4, 2); set(4, 3); set(4, 4); set(4, 5);
    set(4, 12); set(4, 13); set(4, 14); set(4, 15); set(4, 16);
    // Row 5
    set(5, 0); set(5, 1); set(5, 2); set(5, 3); set(5, 4); set(5, 5);
    set(5, 8); set(5, 9); set(5, 10); set(5, 11);
    set(5, 14); set(5, 15); set(5, 16); set(5, 17); set(5, 18); set(5, 19);
    // Rows 6-9: all alive
    for (int row = 6; row < rows; ++row)
        for (int col = 0; col < cols; ++col)
            set(row, col);

    return t;
}

int terrainSnapY(const std::vector<bool>& terrain, int col, const TerrainLayout& layout)
{
    for (int row = 0; row < layout.rows; ++row) {
        if (terrain[row * layout.cols + col])
            return row * layout.blockSize - layout.blockSize / 2;
    }
    // No ground in column — place at bottom
    return layout.rows * layout.blockSize - layout.blockSize / 2;
}
