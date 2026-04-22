#include "delivery_module_api.h"

#include <QDebug>

DeliveryModule::DeliveryModule(LogosAPI* api) : m_api(api), m_client(api->getClient("delivery_module")), m_moduleName(QStringLiteral("delivery_module")) {}

LogosObject* DeliveryModule::ensureReplica() {
    if (!m_eventReplica) {
        LogosObject* replica = m_client->requestObject(m_moduleName);
        if (!replica) {
            qWarning() << "DeliveryModule: failed to acquire remote object for events on" << m_moduleName;
            return nullptr;
        }
        m_eventReplica = replica;
    }
    return m_eventReplica;
}

bool DeliveryModule::on(const QString& eventName, RawEventCallback callback) {
    if (!callback) {
        qWarning() << "DeliveryModule: ignoring empty event callback for" << eventName;
        return false;
    }
    LogosObject* origin = ensureReplica();
    if (!origin) {
        return false;
    }
    m_client->onEvent(origin, eventName, callback);
    return true;
}

bool DeliveryModule::on(const QString& eventName, EventCallback callback) {
    if (!callback) {
        qWarning() << "DeliveryModule: ignoring empty event callback for" << eventName;
        return false;
    }
    return on(eventName, [callback](const QString&, const QVariantList& data) {
        callback(data);
    });
}

void DeliveryModule::setEventSource(LogosObject* source) {
    m_eventSource = source;
}

LogosObject* DeliveryModule::eventSource() const {
    return m_eventSource;
}

void DeliveryModule::trigger(const QString& eventName) {
    trigger(eventName, QVariantList{});
}

void DeliveryModule::trigger(const QString& eventName, const QVariantList& data) {
    if (!m_eventSource) {
        qWarning() << "DeliveryModule: no event source set for trigger" << eventName;
        return;
    }
    m_client->onEventResponse(m_eventSource, eventName, data);
}

void DeliveryModule::trigger(const QString& eventName, LogosObject* source, const QVariantList& data) {
    if (!source) {
        qWarning() << "DeliveryModule: cannot trigger" << eventName << "with null source";
        return;
    }
    m_client->onEventResponse(source, eventName, data);
}

LogosResult DeliveryModule::createNode(const QString& cfg) {
    QVariant _result = m_client->invokeRemoteMethod("delivery_module", "createNode", cfg);
    return _result.value<LogosResult>();
}

void DeliveryModule::createNodeAsync(const QString& cfg, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("delivery_module", "createNode", QVariantList() << cfg, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult DeliveryModule::start() {
    QVariant _result = m_client->invokeRemoteMethod("delivery_module", "start");
    return _result.value<LogosResult>();
}

void DeliveryModule::startAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("delivery_module", "start", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult DeliveryModule::stop() {
    QVariant _result = m_client->invokeRemoteMethod("delivery_module", "stop");
    return _result.value<LogosResult>();
}

void DeliveryModule::stopAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("delivery_module", "stop", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult DeliveryModule::send(const QString& contentTopic, const QString& payload) {
    QVariant _result = m_client->invokeRemoteMethod("delivery_module", "send", contentTopic, payload);
    return _result.value<LogosResult>();
}

void DeliveryModule::sendAsync(const QString& contentTopic, const QString& payload, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("delivery_module", "send", QVariantList{contentTopic, payload}, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult DeliveryModule::subscribe(const QString& contentTopic) {
    QVariant _result = m_client->invokeRemoteMethod("delivery_module", "subscribe", contentTopic);
    return _result.value<LogosResult>();
}

void DeliveryModule::subscribeAsync(const QString& contentTopic, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("delivery_module", "subscribe", QVariantList() << contentTopic, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult DeliveryModule::unsubscribe(const QString& contentTopic) {
    QVariant _result = m_client->invokeRemoteMethod("delivery_module", "unsubscribe", contentTopic);
    return _result.value<LogosResult>();
}

void DeliveryModule::unsubscribeAsync(const QString& contentTopic, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("delivery_module", "unsubscribe", QVariantList() << contentTopic, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult DeliveryModule::getAvailableNodeInfoIDs() {
    QVariant _result = m_client->invokeRemoteMethod("delivery_module", "getAvailableNodeInfoIDs");
    return _result.value<LogosResult>();
}

void DeliveryModule::getAvailableNodeInfoIDsAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("delivery_module", "getAvailableNodeInfoIDs", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult DeliveryModule::getNodeInfo(const QString& nodeInfoId) {
    QVariant _result = m_client->invokeRemoteMethod("delivery_module", "getNodeInfo", nodeInfoId);
    return _result.value<LogosResult>();
}

void DeliveryModule::getNodeInfoAsync(const QString& nodeInfoId, std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("delivery_module", "getNodeInfo", QVariantList() << nodeInfoId, [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

LogosResult DeliveryModule::getAvailableConfigs() {
    QVariant _result = m_client->invokeRemoteMethod("delivery_module", "getAvailableConfigs");
    return _result.value<LogosResult>();
}

void DeliveryModule::getAvailableConfigsAsync(std::function<void(LogosResult)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("delivery_module", "getAvailableConfigs", QVariantList(), [callback](QVariant v) {
        callback(v.isValid() ? qvariant_cast<LogosResult>(v) : LogosResult{});
    }, timeout);
}

void DeliveryModule::initLogos(QVariant logosAPIInstance) {
    m_client->invokeRemoteMethod("delivery_module", "initLogos", logosAPIInstance);
}

void DeliveryModule::initLogosAsync(QVariant logosAPIInstance, std::function<void(void)> callback, Timeout timeout) {
    if (!callback) return;
    m_client->invokeRemoteMethodAsync("delivery_module", "initLogos", QVariantList() << logosAPIInstance, [callback](QVariant v) {
        callback();
    }, timeout);
}

