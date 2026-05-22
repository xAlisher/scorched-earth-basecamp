#include "game_plugin.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>
#include <algorithm>
#include <QtCore/QByteArray>
#include <QtCore/QRandomGenerator>

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

    // Try 1: flat or downhill only — uphill is blocked (walls are impenetrable).
    int snapY = terrainSnapY(terrain_, newCol, layout_);
    if (snapY >= tanks_[idx].y && canStand(snapY)) {
        tanks_[idx].x = newX;
        tanks_[idx].y = snapY;
        return QJsonDocument(QJsonObject{{"x", tanks_[idx].x}}).toJson(QJsonDocument::Compact);
    }

    // Try 2: enter tunnel at current level or below (terrainFloorY scans downward).
    int floorY = terrainFloorY(terrain_, newCol, tanks_[idx].y, layout_);
    if (canStand(floorY)) {
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

    // NOTE: do NOT emit stateChanged here — QML calls getState() in onAnimationComplete().
    // Emitting from inside a synchronous callModule would deadlock (QML thread waiting for
    // processShot result while module waits for QML to ack the stateChanged event).

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
    if (!logosAPI)   return R"({"success":false,"error":"no api"})";
    // Same topic: no-op (avoids double-init).
    if (mpEnabled_ && contentTopic_ == contentTopic) return R"({"success":true})";
    // Different topic: node/handlers already up — just re-subscribe to the new room.
    if (mpEnabled_ && contentTopic_ != contentTopic) {
        deliveryClient_->invokeRemoteMethod("delivery_module", "unsubscribe", contentTopic_);
        contentTopic_ = contentTopic;
        deliveryClient_->invokeRemoteMethod("delivery_module", "subscribe", contentTopic_);
        qDebug() << "ScorchedEarthPlugin: enableMultiplayer re-subscribed topic=" << contentTopic_;
        return R"({"success":true})";
    }

    contentTopic_   = contentTopic;
    deliveryClient_ = logosAPI->getClient("delivery_module");
    if (!deliveryClient_) return R"({"success":false,"error":"no delivery_module client"})";

    // Build node config — random nodeKey per launch (no PeerID collisions).
    // Peer discovery via logos.dev relay mesh; no staticNodes needed.
    QByteArray envPort = qgetenv("SCORCHED_TCP_PORT");
    int requestedPort  = envPort.isEmpty() ? 60000 : envPort.toInt();
    int discv5Port     = 9000 + (requestedPort - 60000);

    QString nodeKey;
    for (int i = 0; i < 32; ++i)
        nodeKey += QString("%1").arg(QRandomGenerator::global()->bounded(256), 2, 16, QChar('0'));

    QString cfg = QString(R"({"logLevel":"INFO","mode":"Core","preset":"logos.dev","relay":true,"tcpPort":%1,"discv5UdpPort":%2,"nodeKey":"%3"})")
                  .arg(requestedPort).arg(discv5Port).arg(nodeKey);

    // 1. Create node (sync — tictactoe pattern)
    deliveryClient_->invokeRemoteMethod("delivery_module", "createNode", cfg);

    // 2. Register event handlers via LogosObject (tictactoe pattern)
    deliveryObject_ = deliveryClient_->requestObject("delivery_module");
    if (deliveryObject_) {
        deliveryClient_->onEvent(deliveryObject_, "messageReceived",
            [this](const QString&, const QVariantList& data) {
                if (data.size() < 3) return;
                if (auto* c = logosAPI->getClient("scorched_earth"))
                    c->onEventResponse(this, "p2pMessage", {data[2]});
            });
        deliveryClient_->onEvent(deliveryObject_, "connectionStateChanged",
            [this](const QString&, const QVariantList& data) {
                QString s = data.size() > 0 ? data[0].toString() : QString();
                if (!s.isEmpty()) {
                    if (auto* c = logosAPI->getClient("scorched_earth"))
                        c->onEventResponse(this, "p2pStatus", {s});
                }
            });
    }

    // 3. Start + subscribe (sync)
    deliveryClient_->invokeRemoteMethod("delivery_module", "start");
    deliveryClient_->invokeRemoteMethod("delivery_module", "subscribe", contentTopic_);

    mpEnabled_ = true;
    qDebug() << "ScorchedEarthPlugin: enableMultiplayer topic=" << contentTopic_;
    return R"({"success":true})";
}

QString ScorchedEarthPlugin::loadState(const QString& json)
{
    QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject()) return R"({"success":false,"error":"invalid json"})";
    QJsonObject obj = doc.object();

    layout_ = TerrainLayout{};   // same defaults as newGame

    if (obj.contains("terrain") && obj["terrain"].isArray()) {
        QJsonArray ta = obj["terrain"].toArray();
        terrain_.clear();
        terrain_.reserve(ta.size());
        for (const auto& v : ta)
            terrain_.push_back(v.toInt() != 0);
    }

    if (obj.contains("tanks") && obj["tanks"].isArray()) {
        QJsonArray ta = obj["tanks"].toArray();
        for (int i = 0; i < 2 && i < ta.size(); ++i) {
            QJsonObject t = ta[i].toObject();
            tanks_[i].x  = t["x"].toInt();
            tanks_[i].y  = t["y"].toInt();
            tanks_[i].hp = t["hp"].toInt(100);
        }
    }

    if (obj.contains("activePlayer")) activePlayer_ = obj["activePlayer"].toInt();
    if (obj.contains("turnSeq"))      turnSeq_      = obj["turnSeq"].toInt();
    if (obj.contains("status"))       status_       = obj["status"].toInt();

    qDebug() << "ScorchedEarthPlugin: loadState activePlayer=" << activePlayer_ << "turnSeq=" << turnSeq_;
    return R"({"success":true})";
}

QString ScorchedEarthPlugin::sendP2PMsg(const QString& jsonPayload)
{
    if (!mpEnabled_ || !deliveryClient_)
        return R"({"success":false,"error":"not initialized"})";
    deliveryClient_->invokeRemoteMethod("delivery_module", "send", contentTopic_, jsonPayload);
    return R"({"success":true})";
}
