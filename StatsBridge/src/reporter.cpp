#include "reporter.h"

#include <LANCommander.Interposer.h>
#include <LANCommander.Interposer.Embedded.h>

#include <cstdio>

namespace utstats
{

namespace
{

const char* OrNull(const std::string& text)
{
    return text.empty() ? nullptr : text.c_str();
}

class InterposerSink final : public Reporter
{
public:
    bool Configure(const DeliverySettings& s) override
    {
        InterposerMatchConfig config{};
        config.structSize      = sizeof(config);
        config.enabled         = 1;
        config.serverUrl       = s.serverUrl.c_str();
        config.token           = s.token.c_str();
        config.gameId          = s.gameId.c_str();
        config.serverId        = s.serverId.c_str();
        config.reporterKind    = "Server";
        config.reporterName    = s.reporterName.c_str();
        config.flushIntervalMs = s.flushIntervalMs;
        return InterposerMatchConfigure(&config) != FALSE;
    }

    MatchHandle Start(const MatchInfo& m) override
    {
        InterposerMatchInfo info{};
        info.structSize    = sizeof(info);
        info.externalId    = OrNull(m.externalId);
        info.map           = OrNull(m.map);
        info.mode          = OrNull(m.mode);
        info.gameVersion   = OrNull(m.gameVersion);
        info.serverName    = OrNull(m.serverName);
        info.serverAddress = OrNull(m.serverAddress);
        info.settingsJson  = OrNull(m.settingsJson);
        info.metadataJson  = OrNull(m.metadataJson);
        return InterposerMatchStart(&info);
    }

    void PlayerJoined(MatchHandle match, const std::string& key, const std::string& name, const std::string& team,
                      long long gameTimeMs) override
    {
        InterposerMatchPlayerJoined(match, key.c_str(), OrNull(name), OrNull(team), gameTimeMs);
    }

    void PlayerLeft(MatchHandle match, const std::string& key, long long gameTimeMs) override
    {
        InterposerMatchPlayerLeft(match, key.c_str(), gameTimeMs);
    }

    void Event(MatchHandle match, const std::string& type, long long gameTimeMs, const std::string& actorKey,
               const std::string& subjectKey, const std::string& payloadJson) override
    {
        InterposerMatchEvent(match, type.c_str(), gameTimeMs, -1, OrNull(actorKey), OrNull(subjectKey),
            OrNull(payloadJson));
    }

    void SetStatistic(MatchHandle match, const std::string& key, const std::string& team, const std::string& name,
                      double value) override
    {
        InterposerMatchSetStatistic(match, OrNull(key), OrNull(team), name.c_str(), value);
    }

    void SetResult(MatchHandle match, const MatchResult& r) override
    {
        InterposerMatchResult result{};
        result.structSize = sizeof(result);
        result.playerKey  = OrNull(r.playerKey);
        result.team       = OrNull(r.team);
        result.rank       = r.rank;
        result.status     = static_cast<int>(r.status);
        result.hasScore   = 1;
        result.score      = r.score;
        result.timeMs     = -1;
        InterposerMatchSetResult(match, &result);
    }

    void End(MatchHandle match, const std::string& reason, bool abandoned) override
    {
        InterposerMatchEnd(match, OrNull(reason), abandoned ? TRUE : FALSE);
    }

    void Flush(MatchHandle match, unsigned timeoutMs) override
    {
        InterposerMatchFlush(match, timeoutMs);
    }

};

class PrintingSink final : public Reporter
{
public:
    bool Configure(const DeliverySettings& s) override
    {
        std::printf("configure url=%s game=%s server=%s reporter=%s\n", s.serverUrl.c_str(), s.gameId.c_str(),
            s.serverId.c_str(), s.reporterName.c_str());
        return true;
    }

    MatchHandle Start(const MatchInfo& m) override
    {
        std::printf("start #%u %s map=%s mode=%s server=%s settings=%s\n", ++m_next, m.externalId.c_str(),
            m.map.c_str(), m.mode.c_str(), m.serverName.c_str(), m.settingsJson.c_str());
        return m_next;
    }

    void PlayerJoined(MatchHandle match, const std::string& key, const std::string& name, const std::string& team,
                      long long t) override
    {
        std::printf("  #%u %8lld joined %s (%s) team=%s\n", match, t, key.c_str(), name.c_str(), team.c_str());
    }

    void PlayerLeft(MatchHandle match, const std::string& key, long long t) override
    {
        std::printf("  #%u %8lld left %s\n", match, t, key.c_str());
    }

    void Event(MatchHandle match, const std::string& type, long long t, const std::string& actor,
               const std::string& subject, const std::string& payload) override
    {
        std::printf("  #%u %8lld %s %s -> %s %s\n", match, t, type.c_str(), actor.c_str(), subject.c_str(),
            payload.c_str());
    }

    void SetStatistic(MatchHandle match, const std::string& key, const std::string& team, const std::string& name,
                      double value) override
    {
        std::printf("  #%u stat %s%s %s = %g\n", match, key.c_str(), team.empty() ? "" : ("team:" + team).c_str(),
            name.c_str(), value);
    }

    void SetResult(MatchHandle match, const MatchResult& r) override
    {
        std::printf("  #%u result %s%s rank=%d status=%d score=%g\n", match, r.playerKey.c_str(),
            r.team.empty() ? "" : (" team:" + r.team).c_str(), r.rank, static_cast<int>(r.status), r.score);
    }

    void End(MatchHandle match, const std::string& reason, bool abandoned) override
    {
        std::printf("end #%u %s%s\n", match, reason.c_str(), abandoned ? " (abandoned)" : "");
    }

    void Flush(MatchHandle, unsigned) override {}


private:
    MatchHandle m_next = 0;
};

bool g_attached = false;

} // namespace

Reporter& InterposerReporter()
{
    static InterposerSink sink;
    return sink;
}

Reporter& PrintingReporter()
{
    static PrintingSink sink;
    return sink;
}

bool AttachInterposer()
{
    if (g_attached)
        return true;

    // FALSE only means another Interposer owns the process and every call forwards to it,
    // which can't happen in this executable; either way the API is usable.
    InterposerEmbeddedAttach();
    g_attached = true;
    return true;
}

void DetachInterposer()
{
    if (!g_attached)
        return;

    InterposerEmbeddedDetach(FALSE);
    g_attached = false;
}

} // namespace utstats
