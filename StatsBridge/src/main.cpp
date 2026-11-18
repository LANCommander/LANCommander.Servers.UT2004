// ut2004-stats-bridge: reports a UT2004 server's games to LANCommander.
//
// The server's LCServer package (LCGameStats) connects over TCP and sends a line for each thing
// that happens in a game (translator.h). This turns them into LANCommander matches, delivered by
// the LANCommander Interposer, embedded: it batches, retries and keeps undelivered matches on
// disk under $INTERPOSER_BASE_DIRECTORY/.interposer/Matches/.
//
// Settings come from the environment:
//
//   MATCH_STATS_SERVER_URL, MATCH_STATS_TOKEN, MATCH_STATS_GAME_ID, MATCH_STATS_SERVER_ID,
//   MATCH_STATS_REPORTER_NAME (default: the server name), MATCH_STATS_FLUSH_INTERVAL (ms),
//   MATCH_STATS_MIN_PLAYERS, MATCH_STATS_RECORD_BOTS
//   UT2004_STATS_BRIDGE_ADDRESS, UT2004_STATS_BRIDGE_PORT   where to listen (127.0.0.1:7790)
//
// ut2004-stats-bridge --dry-run <file>... reads LCServer lines from files and prints what would
// be reported instead of listening.

#include "reporter.h"
#include "translator.h"

#include <nlohmann/json.hpp>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

using nlohmann::json;

namespace
{

std::string Env(const char* name, const char* fallback = "")
{
    const char* value = std::getenv(name);
    return value && *value ? std::string(value) : std::string(fallback);
}

int EnvInt(const char* name, int fallback)
{
    const std::string value = Env(name);

    try
    {
        return value.empty() ? fallback : std::stoi(value);
    }
    catch (...)
    {
        return fallback;
    }
}

bool EnvBool(const char* name, bool fallback)
{
    std::string value = Env(name);

    for (char& c : value)
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));

    if (value == "true" || value == "1" || value == "yes" || value == "on")
        return true;
    if (value == "false" || value == "0" || value == "no" || value == "off")
        return false;
    return fallback;
}

void Log(const std::string& line)
{
    std::fprintf(stdout, "[ut2004-stats-bridge] %s\n", line.c_str());
    std::fflush(stdout);
}

utstats::TranslatorSettings ReadSettings()
{
    utstats::TranslatorSettings s;
    s.minPlayers = std::max(0, EnvInt("MATCH_STATS_MIN_PLAYERS", 1));
    s.recordBots = EnvBool("MATCH_STATS_RECORD_BOTS", true);
    return s;
}

int DryRun(int argc, char** argv)
{
    utstats::Translator translator(utstats::PrintingReporter(), ReadSettings());
    translator.log = Log;

    for (int i = 2; i < argc; ++i)
    {
        std::ifstream file(argv[i]);
        std::string line;

        while (std::getline(file, line))
            translator.OnLine(line);
    }

    translator.Shutdown(0);
    return 0;
}

// The games a previous run was recording when it was killed (docker stop kills the whole
// container without warning the server): resumed under their own id and ended as abandoned,
// so LANCommander gets an end instead of waiting for its housekeeping to close them. The
// Interposer delivers what they already had.
void CloseLeftovers(utstats::Reporter& reporter, const std::string& baseDirectory)
{
    namespace fs = std::filesystem;

    std::error_code error;
    const fs::path spool = fs::path(baseDirectory) / ".interposer" / "Matches";

    for (const auto& entry : fs::directory_iterator(spool, error))
    {
        try
        {
            std::ifstream matchFile(entry.path() / "match.json");
            std::ifstream stateFile(entry.path() / "state.json");

            if (!matchFile || !stateFile)
                continue;

            const json match = json::parse(matchFile);
            const json state = json::parse(stateFile);

            const std::string id = match.value("externalId", "");

            if (id.rfind("ut2004:", 0) != 0 || state.value("ended", false))
                continue;

            utstats::MatchInfo info;
            info.externalId = id;

            if (const utstats::MatchHandle handle = reporter.Start(info))
            {
                reporter.End(handle, "server_shutdown", true);
                Log("Match " + id + " was left open by the last run; ended it as abandoned");
            }
        }
        catch (const std::exception&)
        {
        }
    }
}

std::atomic<bool> g_stopping{false};

void OnSignal(int)
{
    g_stopping = true;
}

struct Connection
{
    int         fd = -1;
    std::string buffer;
};

} // namespace

int main(int argc, char** argv)
{
    if (argc >= 2 && std::string(argv[1]) == "--dry-run")
        return DryRun(argc, argv);

    const std::string address = Env("UT2004_STATS_BRIDGE_ADDRESS", "127.0.0.1");
    const int         port    = EnvInt("UT2004_STATS_BRIDGE_PORT", 7790);

    utstats::DeliverySettings delivery;
    delivery.serverUrl       = Env("MATCH_STATS_SERVER_URL");
    delivery.token           = Env("MATCH_STATS_TOKEN");
    delivery.gameId          = Env("MATCH_STATS_GAME_ID");
    delivery.serverId        = Env("MATCH_STATS_SERVER_ID");
    delivery.reporterName    = Env("MATCH_STATS_REPORTER_NAME");
    delivery.flushIntervalMs = EnvInt("MATCH_STATS_FLUSH_INTERVAL", 0);

    utstats::AttachInterposer();
    utstats::Reporter& reporter = utstats::InterposerReporter();

    if (!reporter.Configure(delivery))
        Log("the Interposer refused the MATCH_STATS_* settings; see its log in .interposer/Logs/");
    else if (const std::string base = Env("INTERPOSER_BASE_DIRECTORY"); !base.empty())
        CloseLeftovers(reporter, base);

    utstats::Translator translator(reporter, ReadSettings());
    translator.log = Log;

    // Without a reporter name of its own, the server reports as the name it gives players
    const bool namedReporter = !delivery.reporterName.empty();
    translator.onServerName = [&](const std::string& name) {
        if (namedReporter || name.empty() || name == delivery.reporterName)
            return;

        delivery.reporterName = name;
        reporter.Configure(delivery);
    };

    const int listener = socket(AF_INET, SOCK_STREAM, 0);
    const int yes = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    sockaddr_in bindAddress{};
    bindAddress.sin_family = AF_INET;
    bindAddress.sin_port   = htons(static_cast<uint16_t>(port));

    if (inet_pton(AF_INET, address.c_str(), &bindAddress.sin_addr) != 1 ||
        bind(listener, reinterpret_cast<sockaddr*>(&bindAddress), sizeof(bindAddress)) != 0 ||
        listen(listener, 4) != 0)
    {
        Log("could not listen on " + address + ":" + std::to_string(port) + ": " + std::strerror(errno));
        return 1;
    }

    std::signal(SIGTERM, OnSignal);
    std::signal(SIGINT, OnSignal);
    std::signal(SIGPIPE, SIG_IGN);

    Log("listening on " + address + ":" + std::to_string(port) + "; reporting to " +
        (delivery.serverUrl.empty() ? std::string("nobody (MATCH_STATS_SERVER_URL is empty)") : delivery.serverUrl));

    std::vector<Connection> connections;

    while (!g_stopping)
    {
        std::vector<pollfd> fds;
        fds.push_back({listener, POLLIN, 0});

        for (const Connection& c : connections)
            fds.push_back({c.fd, POLLIN, 0});

        if (poll(fds.data(), fds.size(), 500) < 0)
            continue;

        if (fds[0].revents & POLLIN)
        {
            const int fd = accept(listener, nullptr, nullptr);

            if (fd >= 0)
            {
                connections.push_back({fd, {}});
                Log("the server connected");
            }
        }

        for (std::size_t i = 1; i < fds.size(); ++i)
        {
            if (!(fds[i].revents & (POLLIN | POLLHUP | POLLERR)))
                continue;

            Connection& c = connections[i - 1];
            char chunk[4096];
            const ssize_t n = recv(c.fd, chunk, sizeof(chunk), 0);

            if (n <= 0)
            {
                close(c.fd);
                c.fd = -1;
                Log("the server disconnected");
                continue;
            }

            c.buffer.append(chunk, static_cast<std::size_t>(n));

            std::size_t newline;
            while ((newline = c.buffer.find('\n')) != std::string::npos)
            {
                translator.OnLine(c.buffer.substr(0, newline));
                c.buffer.erase(0, newline + 1);
            }

            // A line this long is garbage
            if (c.buffer.size() > 1 << 20)
                c.buffer.clear();
        }

        connections.erase(std::remove_if(connections.begin(), connections.end(),
            [](const Connection& c) { return c.fd < 0; }), connections.end());
    }

    Log("stopping");
    translator.Shutdown(5000);
    utstats::DetachInterposer();
    return 0;
}
