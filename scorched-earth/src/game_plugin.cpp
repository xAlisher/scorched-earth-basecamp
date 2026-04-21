#include "game_plugin.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <algorithm>

ScorchedEarthPlugin::ScorchedEarthPlugin()
{
    qDebug() << "ScorchedEarthPlugin: initialized";
}

void ScorchedEarthPlugin::snapTankY(int idx)
{
    tanks_[idx].y = terrainSnapY(terrain_, tanks_[idx].x / layout_.blockSize, layout_);
}

QString ScorchedEarthPlugin::buildState() const
{
    QJsonObject obj;
    obj["status"]       = status_;
    obj["activePlayer"] = activePlayer_;
    obj["turnSeq"]      = turnSeq_;
    obj["windForce"]    = 0;  // stored separately if needed; 0 for now

    // Terrain: flat array of 0/1
    QJsonArray terrainArr;
    for (bool b : terrain_)
        terrainArr.append(b ? 1 : 0);
    obj["terrain"] = terrainArr;

    // Tanks
    QJsonArray tanksArr;
    for (int i = 0; i < 2; ++i) {
        QJsonObject t;
        t["x"]  = tanks_[i].x;
        t["y"]  = tanks_[i].y;
        t["hp"] = tanks_[i].hp;
        tanksArr.append(t);
    }
    obj["tanks"] = tanksArr;

    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

QString ScorchedEarthPlugin::newGame(int /*cols*/, int /*rows*/, int /*windForce*/)
{
    layout_       = TerrainLayout{};
    terrain_      = buildHardcodedTerrain();
    activePlayer_ = 1;
    turnSeq_      = 0;
    status_       = 0;

    // Tank initial positions
    tanks_[0].x  = 2 * layout_.blockSize;
    tanks_[0].hp = 100;
    snapTankY(0);

    tanks_[1].x  = 17 * layout_.blockSize;
    tanks_[1].hp = 100;
    snapTankY(1);

    qDebug() << "ScorchedEarthPlugin: newGame";
    return buildState();
}

QString ScorchedEarthPlugin::getState()
{
    return buildState();
}

int ScorchedEarthPlugin::moveTank(int tankId, int direction)
{
    if (tankId < 1 || tankId > 2) return -1;
    int idx = tankId - 1;

    const int maxX = (layout_.cols - 1) * layout_.blockSize;
    int newX = std::clamp(tanks_[idx].x + direction * layout_.blockSize, 0, maxX);
    int newCol = newX / layout_.blockSize;

    static constexpr int TANK_H = 20; // visual body height in pixels

    // Returns true if the tank can stand at pixel y in newCol:
    // floor block exists at y and no ceiling block intersects the tank body [y-TANK_H, y).
    auto canStand = [&](int y) -> bool {
        int floorRow = y / layout_.blockSize;
        if (floorRow < 0 || floorRow >= layout_.rows) return false;
        if (!terrain_[floorRow * layout_.cols + newCol]) return false;
        for (int r = 0; r < floorRow; ++r) {
            if (!terrain_[r * layout_.cols + newCol]) continue;
            int blockBottom = (r + 1) * layout_.blockSize;
            if (blockBottom > y - TANK_H) return false; // ceiling clips body
        }
        return true;
    };

    const int bs = layout_.blockSize;

    // Try 1: step up/down via topmost surface (normal staircase movement).
    int snapY = terrainSnapY(terrain_, newCol, layout_);
    if (snapY >= tanks_[idx].y - bs && canStand(snapY)) {
        tanks_[idx].x = newX;
        tanks_[idx].y = snapY;
        return tanks_[idx].x;
    }

    // Try 2: stay at current level and enter a tunnel (floor at same height or below).
    int floorY = terrainFloorY(terrain_, newCol, tanks_[idx].y, layout_);
    if (canStand(floorY) && floorY >= tanks_[idx].y - bs) {
        tanks_[idx].x = newX;
        tanks_[idx].y = floorY;
        return tanks_[idx].x;
    }

    return tanks_[idx].x; // blocked
}

QString ScorchedEarthPlugin::processShot(int tankId, double angle, double power)
{
    if (tankId < 1 || tankId > 2 || status_ != 0)
        return QJsonDocument(QJsonObject{{"hit", false}, {"error", "invalid"}}).toJson(QJsonDocument::Compact);

    int idx = tankId - 1;
    float startX = tanks_[idx].x + 24;   // fire from horizontal center of tank body
    float startY = tanks_[idx].y;

    auto pts = trajectory(startX, startY, (float)angle, (float)power);

    std::vector<TankPos> tankPositions;
    for (int i = 0; i < 2; ++i)
        tankPositions.push_back({tanks_[i].x, tanks_[i].y});

    Collision col = firstCollision(pts, terrain_, layout_, tankPositions, idx);

    QJsonObject result;
    result["hit"]    = col.hit;
    result["tankId"] = col.isTank ? (col.tankId + 1) : -1;
    result["seq"]    = turnSeq_;

    QJsonArray removed;
    if (col.hit && !col.isTank && col.blockCol >= 0) {
        // Destroy the hit block
        terrain_[col.blockRow * layout_.cols + col.blockCol] = false;
        QJsonArray block;
        block.append(col.blockCol);
        block.append(col.blockRow);
        removed.append(block);

        // Drop any tank whose floor block was just destroyed
        for (int i = 0; i < 2; ++i) {
            int tankCol      = tanks_[i].x / layout_.blockSize;
            int tankFloorRow = tanks_[i].y / layout_.blockSize;
            if (tankCol == col.blockCol && tankFloorRow == col.blockRow) {
                int newY = terrainFloorY(terrain_, tankCol, tanks_[i].y, layout_);
                if (newY >= layout_.rows * layout_.blockSize) {
                    // Fell off the map — instant death
                    tanks_[i].hp = 0;
                    status_ = (i == 0) ? 2 : 1;
                } else {
                    tanks_[i].y = newY;
                    // Crush: if the other tank occupies the same column and floor, it dies
                    int other = 1 - i;
                    int otherCol = tanks_[other].x / layout_.blockSize;
                    if (otherCol == tankCol && tanks_[other].y == newY && status_ == 0) {
                        tanks_[other].hp = 0;
                        status_ = (other == 0) ? 2 : 1;
                        qDebug() << "processShot: tank P" << (i+1) << "crushed P" << (other+1);
                    }
                }
            }
        }
    }
    result["removedBlocks"] = removed;

    if (col.hit && col.isTank) {
        int hitIdx = col.tankId;
        tanks_[hitIdx].hp = 0;
        status_ = (hitIdx == 0) ? 2 : 1;  // other player wins
    }

    // Flip active player
    activePlayer_ = (activePlayer_ == 1) ? 2 : 1;
    ++turnSeq_;

    result["status"] = status_;

    qDebug() << "processShot P" << tankId
             << "angle" << angle << "power" << power
             << "| hit=" << col.hit
             << (col.isTank ? QString("tank P%1 hp=%2").arg(col.tankId+1).arg(tanks_[col.tankId].hp)
                            : (col.hit ? QString("block[%1,%2]").arg(col.blockCol).arg(col.blockRow)
                                       : QString("miss")))
             << "| status=" << status_;

    // Emit stateChanged event
    if (logosAPI) {
        auto* client = logosAPI->getClient("scorched_earth");
        if (client)
            client->onEventResponse(this, "stateChanged", {buildState()});
    }

    return QJsonDocument(result).toJson(QJsonDocument::Compact);
}

int ScorchedEarthPlugin::gameStatus()
{
    return status_;
}

int ScorchedEarthPlugin::activePlayer()
{
    return activePlayer_;
}
