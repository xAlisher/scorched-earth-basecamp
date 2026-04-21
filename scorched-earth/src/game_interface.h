#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>
#include "interface.h"

class ScorchedEarthInterface : public PluginInterface
{
public:
    virtual ~ScorchedEarthInterface() {}

    // Start a new game. Returns JSON state snapshot.
    Q_INVOKABLE virtual QString newGame(int cols, int rows, int windForce) = 0;

    // Full game state as JSON.
    Q_INVOKABLE virtual QString getState() = 0;

    // Move tank left (-1) or right (+1) by one block. Returns new x position.
    Q_INVOKABLE virtual int moveTank(int tankId, int direction) = 0;

    // Fire shot. Returns JSON: {hit, tankId, removedBlocks, seq, status}
    Q_INVOKABLE virtual QString processShot(int tankId, double angle, double power) = 0;

    // 0=ongoing, 1=p1wins, 2=p2wins
    Q_INVOKABLE virtual int gameStatus() = 0;

    // Active player: 1 or 2
    Q_INVOKABLE virtual int activePlayer() = 0;

    // P2P multiplayer: initialize delivery_module and subscribe to contentTopic.
    // Returns {"success":true} or {"success":false,"error":"..."}.
    Q_INVOKABLE virtual QString enableMultiplayer(const QString& contentTopic) = 0;

    // P2P multiplayer: send a JSON payload to the current content topic.
    Q_INVOKABLE virtual QString sendP2PMsg(const QString& jsonPayload) = 0;

signals:
    void eventResponse(const QString& name, const QVariantList& data);
};

#define ScorchedEarthInterface_iid "org.logos.ScorchedEarthInterface"
Q_DECLARE_INTERFACE(ScorchedEarthInterface, ScorchedEarthInterface_iid)
