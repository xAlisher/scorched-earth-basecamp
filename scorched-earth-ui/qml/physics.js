.pragma library

// CRITICAL: constants MUST match physics.cpp exactly.
// Determinism test (issue #31) diffs JS output vs C++ output byte-for-byte.
var GRAVITY      = 0.3
var BLOCK_SIZE   = 48
var COLS         = 20
var ROWS         = 10
var CANVAS_WIDTH = 960
var CANVAS_HEIGHT= 480

// Returns [{x,y}, ...] trajectory until out-of-bounds.
// Mirrors: std::vector<PhysPoint> trajectory(...) in physics.cpp
function trajectory(startX, startY, angleDeg, power) {
    var pts = []
    var rad = angleDeg * Math.PI / 180.0
    var vx = Math.cos(rad) * power * 0.15
    var vy = -Math.sin(rad) * power * 0.15
    var x  = startX
    var y  = startY
    while (x >= 0 && x < CANVAS_WIDTH && y < CANVAS_HEIGHT) {
        pts.push({ x: x, y: y })
        x  += vx
        y  += vy
        vy += GRAVITY
    }
    return pts
}

// Returns first collision along pts with terrain or tanks.
// Mirrors: Collision firstCollision(...) in physics.cpp
// terrain: flat array of 0/1, length COLS*ROWS, row-major
// tanks:   [{x,y}, ...]  (0-based indices)
function firstCollision(pts, terrain, tanks) {
    for (var i = 0; i < pts.length; i++) {
        var p = pts[i]
        for (var t = 0; t < tanks.length; t++) {
            if (Math.abs(p.x - tanks[t].x) < BLOCK_SIZE &&
                Math.abs(p.y - tanks[t].y) < BLOCK_SIZE) {
                return { hit: true, isTank: true, tankId: t,
                         blockCol: -1, blockRow: -1, point: p }
            }
        }
        var col = Math.floor(p.x / BLOCK_SIZE)
        var row = Math.floor(p.y / BLOCK_SIZE)
        if (col >= 0 && col < COLS && row >= 0 && row < ROWS) {
            if (terrain[row * COLS + col]) {
                return { hit: true, isTank: false, tankId: -1,
                         blockCol: col, blockRow: row, point: p }
            }
        }
    }
    return { hit: false }
}
