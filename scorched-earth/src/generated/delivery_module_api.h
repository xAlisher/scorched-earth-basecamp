#pragma once
#include <QString>
#include <QVariant>
#include <QStringList>
#include <QJsonArray>
#include <QVariantList>
#include <QVariantMap>
#include <functional>
#include <utility>
#include "logos_types.h"
#include "logos_api.h"
#include "logos_api_client.h"
#include "logos_object.h"

class DeliveryModule {
public:
    explicit DeliveryModule(LogosAPI* api);

    using RawEventCallback = std::function<void(const QString&, const QVariantList&)>;
    using EventCallback = std::function<void(const QVariantList&)>;

    bool on(const QString& eventName, RawEventCallback callback);
    bool on(const QString& eventName, EventCallback callback);
    void setEventSource(LogosObject* source);
    LogosObject* eventSource() const;
    void trigger(const QString& eventName);
    void trigger(const QString& eventName, const QVariantList& data);
    template<typename... Args>
    void trigger(const QString& eventName, Args&&... args) {
        trigger(eventName, packVariantList(std::forward<Args>(args)...));
    }
    void trigger(const QString& eventName, LogosObject* source, const QVariantList& data);
    template<typename... Args>
    void trigger(const QString& eventName, LogosObject* source, Args&&... args) {
        trigger(eventName, source, packVariantList(std::forward<Args>(args)...));
    }

    LogosResult createNode(const QString& cfg);
    void createNodeAsync(const QString& cfg, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult start();
    void startAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult stop();
    void stopAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult send(const QString& contentTopic, const QString& payload);
    void sendAsync(const QString& contentTopic, const QString& payload, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult subscribe(const QString& contentTopic);
    void subscribeAsync(const QString& contentTopic, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult unsubscribe(const QString& contentTopic);
    void unsubscribeAsync(const QString& contentTopic, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult getAvailableNodeInfoIDs();
    void getAvailableNodeInfoIDsAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult getNodeInfo(const QString& nodeInfoId);
    void getNodeInfoAsync(const QString& nodeInfoId, std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    LogosResult getAvailableConfigs();
    void getAvailableConfigsAsync(std::function<void(LogosResult)> callback, Timeout timeout = Timeout());
    void initLogos(QVariant logosAPIInstance);
    void initLogosAsync(QVariant logosAPIInstance, std::function<void()> callback, Timeout timeout = Timeout());

private:
    LogosObject* ensureReplica();
    template<typename... Args>
    static QVariantList packVariantList(Args&&... args) {
        QVariantList list;
        list.reserve(sizeof...(Args));
        using Expander = int[];
        (void)Expander{0, (list.append(QVariant::fromValue(std::forward<Args>(args))), 0)...};
        return list;
    }
    LogosAPI* m_api;
    LogosAPIClient* m_client;
    QString m_moduleName;
    LogosObject* m_eventReplica = nullptr;
    LogosObject* m_eventSource = nullptr;
};
