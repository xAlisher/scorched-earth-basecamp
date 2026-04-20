#pragma once

#include <vector>

// 20 cols × 10 rows, BLOCK_SIZE=48
// Row 0 = top. O=alive block, .=air.
//
// Row 0-1: all air
// Row 2:   . . . . O O . . . . . . O O . . . . . .
// Row 3:   . . O O O O . . . . . . O O O O . . . .
// Row 4:   . O O O O O . . . . . . O O O O O . . .
// Row 5:   O O O O O O . . O O O O . . O O O O O O
// Row 6-9: all O
//
// Tank 1: col 2, Tank 2: col 17

struct TerrainLayout {
    int cols = 20;
    int rows = 10;
    int blockSize = 48;
};

std::vector<bool> buildHardcodedTerrain();

// Scan column downward from top; return y = first-alive-row * blockSize - blockSize/2
int terrainSnapY(const std::vector<bool>& terrain, int col, const TerrainLayout& layout);
