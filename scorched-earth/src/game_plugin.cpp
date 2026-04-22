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

ScorchedEarthPlugin::~ScorchedEarthPlugin()
{
    delete delivery_;
    delivery_ = nullptr;
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

QString ScorchedEarthPlugin::moveTank(int tankId, int direction)
{
    if (tankId < 1 || tankId > 2)
        return R"({"x":-1})";
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
        return QJsonDocument(QJsonObject{{"x", tanks_[idx].x}}).toJson(QJsonDocument::Compact);
    }

    // Try 2: stay at current level and enter a tunnel (floor at same height or below).
    int floorY = terrainFloorY(terrain_, newCol, tanks_[idx].y, layout_);
    if (canStand(floorY) && floorY >= tanks_[idx].y - bs) {
        tanks_[idx].x = newX;
        tanks_[idx].y = floorY;
        return QJsonDocument(QJsonObject{{"x", tanks_[idx].x}}).toJson(QJsonDocument::Compact);
    }

    return QJsonDocument(QJsonObject{{"x", tanks_[idx].x}}).toJson(QJsonDocument::Compact); // blocked
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

QString ScorchedEarthPlugin::gameStatus()
{
    return QJsonDocument(QJsonObject{{"status", status_}}).toJson(QJsonDocument::Compact);
}

QString ScorchedEarthPlugin::activePlayer()
{
    return QJsonDocument(QJsonObject{{"player", activePlayer_}}).toJson(QJsonDocument::Compact);
}

QString ScorchedEarthPlugin::enableMultiplayer(const QString& contentTopic)
{
    if (!logosAPI) return R"({"success":false,"error":"no api"})";
    contentTopic_ = contentTopic;

    // Lazy-init typed DeliveryModule client
    if (!delivery_)
        delivery_ = new DeliveryModule(logosAPI);

    emitP2PStatus("Connecting... (1/3) creating node");
    QThread* t = QThread::create([this]() { doMultiplayerSetup(); });
    connect(t, &QThread::finished, t, &QThread::deleteLater);
    t->start();
    return R"({"success":true})";
}

void ScorchedEarthPlugin::doMultiplayerSetup()
{
    if (!delivery_) { emitP2PStatus("Error: no delivery client"); return; }

    // Use SCORCHED_TCP_PORT to determine role:
    //   not set / 60000 → HOST: fixed node key so PeerID is deterministic
    //   any other port  → GUEST: connect directly to HOST's known multiaddr
    // Fixed key: 0102…1f20 → PeerID 16Uiu2HAm4Ms862Gnqafssgvik4JJ1LuqWMcKNipq4nm2UaoLRbeP
    QByteArray envPort = qgetenv("SCORCHED_TCP_PORT");
    int requestedPort = envPort.isEmpty() ? 60000 : envPort.toInt();
    bool isFirstNode  = (requestedPort == 60000);

    QString cfg;
    if (isFirstNode) {
        cfg = R"({"logLevel":"DEBUG","mode":"Core","preset":"logos.dev","relay":true,"tcpPort":60000,"nodeKey":"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"})";
    } else {
        cfg = QString(R"({"logLevel":"DEBUG","mode":"Core","preset":"logos.dev","relay":true,"tcpPort":%1,"staticNodes":["/ip4/127.0.0.1/tcp/60000/p2p/16Uiu2HAm4Ms862Gnqafssgvik4JJ1LuqWMcKNipq4nm2UaoLRbeP"]})")
                  .arg(requestedPort);
    }

    LogosResult r1 = delivery_->createNode(cfg);
    if (!r1.success) { emitP2PStatus("Error createNode: " + r1.getError()); return; }

    emitP2PStatus("Connecting... (2/3) starting");
    LogosResult r2 = delivery_->start();
    if (!r2.success) { emitP2PStatus("Error start: " + r2.getError()); return; }

    emitP2PStatus("Connecting... (3/3) subscribing");
    LogosResult r3 = delivery_->subscribe(contentTopic_);
    if (!r3.success) { emitP2PStatus("Error subscribe: " + r3.getError()); return; }

    // Wire events via typed API
    delivery_->on("messageReceived", [this](const QVariantList& data) {
        if (!logosAPI || data.size() < 3) return;
        if (auto* c = logosAPI->getClient("scorched_earth"))
            c->onEventResponse(this, "p2pMessage", {data[2]});
    });
    delivery_->on("connectionStateChanged", [this](const QVariantList& data) {
        QString status = data.size() > 0 ? data[0].toString() : QString();
        if (!status.isEmpty())
            emitP2PStatus(status);
    });

    emitP2PStatus("Connected");
}

void ScorchedEarthPlugin::emitP2PStatus(const QString& status)
{
    QMetaObject::invokeMethod(this, [this, status]() {
        if (logosAPI) {
            if (auto* c = logosAPI->getClient("scorched_earth"))
                c->onEventResponse(this, "p2pStatus", {status});
        }
    }, Qt::QueuedConnection);
}

QString ScorchedEarthPlugin::sendP2PMsg(const QString& jsonPayload)
{
    if (!delivery_ || contentTopic_.isEmpty())
        return R"({"success":false,"error":"not initialized"})";
    LogosResult r = delivery_->send(contentTopic_, jsonPayload);
    return r.success ? R"({"success":true})" : R"({"success":false,"error":")" + r.getError() + R"("})";
}
