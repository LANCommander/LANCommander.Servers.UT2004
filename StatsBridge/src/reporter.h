// Where the translated matches go: the Interposer's match statistics API, behind an interface
// so the translator can be driven without it (--dry-run prints the calls instead).

#pragma once

#include <cstdint>
#include <string>

namespace utstats
{

using MatchHandle = std::uint32_t;

enum class ResultStatus { Finished = 0, DidNotFinish = 1, Defeated = 3 };

struct MatchInfo
{
    std::string externalId;
    std::string map;
    std::string mode;
    std::string gameVersion;
    std::string serverName;
    std::string serverAddress;
    std::string settingsJson;
    std::string metadataJson;
};

struct MatchResult
{
    std::string  playerKey;
    std::string  team;
    int          rank = 0;
    ResultStatus status = ResultStatus::Finished;
    double       score = 0;
};

struct DeliverySettings
{
    std::string serverUrl;
    std::string token;
    std::string gameId;
    std::string serverId;
    std::string reporterName;
    int         flushIntervalMs = 0;
};

class Reporter
{
public:
    virtual ~Reporter() = default;

    virtual bool        Configure(const DeliverySettings& settings) = 0;
    virtual MatchHandle Start(const MatchInfo& info) = 0;
    virtual void        PlayerJoined(MatchHandle match, const std::string& key, const std::string& name,
                                     const std::string& team, long long gameTimeMs) = 0;
    virtual void        PlayerLeft(MatchHandle match, const std::string& key, long long gameTimeMs) = 0;
    virtual void        Event(MatchHandle match, const std::string& type, long long gameTimeMs,
                              const std::string& actorKey, const std::string& subjectKey,
                              const std::string& payloadJson) = 0;
    virtual void        SetStatistic(MatchHandle match, const std::string& key, const std::string& team,
                                     const std::string& name, double value) = 0;
    virtual void        SetResult(MatchHandle match, const MatchResult& result) = 0;
    virtual void        End(MatchHandle match, const std::string& reason, bool abandoned) = 0;
    virtual void        Flush(MatchHandle match, unsigned timeoutMs) = 0;

};

// The embedded Interposer. Attach() once before anything else, Detach() last.
Reporter& InterposerReporter();
bool      AttachInterposer();
void      DetachInterposer();

// Prints every call to stdout and sends nothing.
Reporter& PrintingReporter();

} // namespace utstats
