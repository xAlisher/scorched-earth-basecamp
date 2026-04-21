#pragma once

#include <QtCore/QObject>
#include "game_interface.h"
#include "terrain.h"
#include "physics.h"
#include "logos_api.h"
#include "logos_api_client.h"

struct Tank {
    int x = 0;
    int y = 0;
    int hp = 100;
};

class ScorchedEarthPlugin : public QObject, public ScorchedEarthInterface
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID ScorchedEarthInterface_iid FILE "plugin_metadata.json")
    Q_INTERFACES(ScorchedEarthInterface PluginInterface)

public:
    ScorchedEarthPlugin();
    ~ScorchedEarthPlugin() override = default;

    Q_INVOKABLE QString newGame(int cols, int rows, int windForce) override;
    Q_INVOKABLE QString getState() override;
    Q_INVOKABLE int     moveTank(int tankId, int direction) override;
    Q_INVOKABLE QString processShot(int tankId, double angle, double power) override;
    Q_INVOKABLE int     gameStatus() override;
    Q_INVOKABLE int     activePlayer() override;

    QString name()    const override { return "scorched_earth"; }
    QString version() const override { return "0.1.0"; }
    Q_INVOKABLE void initLogos(LogosAPI* api) { logosAPI = api; }

signals:
    void eventResponse(const QString& name, const QVariantList& data);

private:
    TerrainLayout layout_;
    std::vector<bool> terrain_;
    Tank tanks_[2];
    int activePlayer_ = 1;
    int turnSeq_      = 0;
    int status_       = 0;   // 0=ongoing, 1=p1wins, 2=p2wins

    QString buildState() const;
    void snapTankY(int idx);
};
