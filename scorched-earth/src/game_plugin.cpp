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
    tanks_[idx].x = std::clamp(tanks_[idx].x + direction * layout_.blockSize, 0, maxX);
    snapTankY(idx);

    return tanks_[idx].x;
}

QString ScorchedEarthPlugin::processShot(int tankId, float angle, float power)
{
    if (tankId < 1 || tankId > 2 || status_ != 0)
        return QJsonDocument(QJsonObject{{"hit", false}, {"error", "invalid"}}).toJson(QJsonDocument::Compact);

    int idx = tankId - 1;
    float startX = tanks_[idx].x;
    float startY = tanks_[idx].y;

    auto pts = trajectory(startX, startY, angle, power);

    std::vector<TankPos> tankPositions;
    for (int i = 0; i < 2; ++i)
        tankPositions.push_back({tanks_[i].x, tanks_[i].y});

    Collision col = firstCollision(pts, terrain_, layout_, tankPositions);

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
    }
    result["removedBlocks"] = removed;

    if (col.hit && col.isTank) {
        int hitIdx = col.tankId;
        tanks_[hitIdx].hp -= 25;
        if (tanks_[hitIdx].hp <= 0) {
            tanks_[hitIdx].hp = 0;
            status_ = (hitIdx == 0) ? 2 : 1;  // other player wins
        }
    }

    // Flip active player
    activePlayer_ = (activePlayer_ == 1) ? 2 : 1;
    ++turnSeq_;

    result["status"] = status_;

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
