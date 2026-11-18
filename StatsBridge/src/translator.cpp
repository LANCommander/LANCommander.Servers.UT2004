#include "translator.h"

#include <nlohmann/json.hpp>

#include <cstdlib>
#include <regex>

using nlohmann::json;

namespace utstats
{

namespace
{

std::vector<std::string> Split(const std::string& line)
{
    std::vector<std::string> fields;
    std::size_t start = 0;

    while (true)
    {
        const std::size_t tab = line.find('\t', start);
        fields.push_back(line.substr(start, tab == std::string::npos ? std::string::npos : tab - start));

        if (tab == std::string::npos)
            break;

        start = tab + 1;
    }

    return fields;
}

const std::string& Field(const std::vector<std::string>& f, std::size_t i)
{
    static const std::string empty;
    return i < f.size() ? f[i] : empty;
}

long long Time(const std::vector<std::string>& f, std::size_t i)
{
    return std::strtoll(Field(f, i).c_str(), nullptr, 10);
}

double Number(const std::string& text)
{
    return std::strtod(text.c_str(), nullptr);
}

bool IsBot(const std::string& key)
{
    return key.rfind("bot:", 0) == 0;
}

} // namespace

std::string FromLatin1(const std::string& text)
{
    std::string out;
    out.reserve(text.size());

    for (const unsigned char c : text)
    {
        if (c < 0x80)
        {
            out += static_cast<char>(c);
        }
        else
        {
            out += static_cast<char>(0xC0 | (c >> 6));
            out += static_cast<char>(0x80 | (c & 0x3F));
        }
    }

    return out;
}

std::string PayloadJson(const std::vector<std::string>& fields, std::size_t first)
{
    static const std::regex number(R"(-?(0|[1-9][0-9]*)(\.[0-9]+)?)");

    json payload = json::object();

    for (std::size_t i = first; i < fields.size(); ++i)
    {
        const std::size_t eq = fields[i].find('=');

        if (eq == std::string::npos || eq == 0)
            continue;

        const std::string key   = fields[i].substr(0, eq);
        const std::string value = fields[i].substr(eq + 1);

        if (value == "true" || value == "false")
            payload[key] = value == "true";
        else if (std::regex_match(value, number))
            payload[key] = value.find('.') == std::string::npos ? json(std::strtoll(value.c_str(), nullptr, 10))
                                                                : json(Number(value));
        else
            payload[key] = value;
    }

    return payload.empty() ? std::string() : payload.dump();
}

Translator::Translator(Reporter& reporter, TranslatorSettings settings)
    : m_reporter(reporter), m_settings(settings)
{
}

void Translator::OnLine(const std::string& raw)
{
    std::string line = FromLatin1(raw);

    if (!line.empty() && line.back() == '\r')
        line.pop_back();

    if (line.empty())
        return;

    const std::vector<std::string> f = Split(line);
    const std::string& kind = f[0];

    if (kind == "HELLO")
    {
        m_serverName = Field(f, 2);

        if (onServerName)
            onServerName(m_serverName);
    }
    else if (kind == "START")  OnStart(f);
    else if (kind == "JOIN")   OnJoin(f);
    else if (kind == "LEAVE")  OnLeave(f);
    else if (kind == "EVENT")  OnEvent(f);
    else if (kind == "PLAYER") OnPlayer(f);
    else if (kind == "TEAM")   OnTeam(f);
    else if (kind == "END")    OnEnd(f);
    else if (log)
        log("ignoring an unknown line: " + kind);
}

void Translator::OnStart(const std::vector<std::string>& f)
{
    const std::string& id = Field(f, 2);

    if (id.empty())
        return;

    // LCServer reconnected: the same game
    if (m_game && m_game->id == id)
        return;

    if (m_game)
        EndGame("map_changed", true);

    Game game;
    game.id                 = id;
    game.info.externalId    = id;
    game.info.map           = Field(f, 3);
    game.info.mode          = Field(f, 4);
    game.info.gameVersion   = "3339";
    game.info.serverName    = m_serverName;
    game.info.settingsJson  = PayloadJson(f, 6);

    if (!Field(f, 5).empty())
        game.info.metadataJson = json{{"map_title", Field(f, 5)}}.dump();

    m_game = std::move(game);

    if (log)
        log("game " + id + " started: " + m_game->info.map + " (" + m_game->info.mode + ")");

    // With MinPlayers 0, it's reported from the start
    NoteHuman(std::string());
}

void Translator::OnJoin(const std::vector<std::string>& f)
{
    const std::string key = Recorded(Field(f, 2));

    if (!m_game || key.empty())
        return;

    if (!IsBot(key))
        NoteHuman(key);

    Report([this, key, name = Field(f, 3), team = Field(f, 4), t = Time(f, 1)](MatchHandle match) {
        m_reporter.PlayerJoined(match, key, name, team, t);
    });
}

void Translator::OnLeave(const std::vector<std::string>& f)
{
    const std::string key = Recorded(Field(f, 2));

    if (!m_game || key.empty())
        return;

    Report([this, key, t = Time(f, 1)](MatchHandle match) {
        m_reporter.PlayerLeft(match, key, t);
    });
}

void Translator::OnEvent(const std::vector<std::string>& f)
{
    const std::string& type = Field(f, 2);

    if (!m_game || type.empty())
        return;

    const std::string actor   = Recorded(Field(f, 3));
    const std::string subject = Recorded(Field(f, 4));

    // An event between unrecorded bots only
    if (actor.empty() && subject.empty() && (!Field(f, 3).empty() || !Field(f, 4).empty()))
        return;

    Report([this, type, actor, subject, payload = PayloadJson(f, 5), t = Time(f, 1)](MatchHandle match) {
        m_reporter.Event(match, type, t, actor, subject, payload);
    });
}

void Translator::OnPlayer(const std::vector<std::string>& f)
{
    const std::string key = Recorded(Field(f, 1));

    if (!m_game || key.empty())
        return;

    Totals& t = m_game->totals[key];
    t.team    = Field(f, 2);
    t.present = Field(f, 3) == "1";
    t.stats.clear();

    for (std::size_t i = 4; i < f.size(); ++i)
    {
        const std::size_t eq = f[i].find('=');

        if (eq == std::string::npos || eq == 0)
            continue;

        const std::string name  = f[i].substr(0, eq);
        const double      value = Number(f[i].substr(eq + 1));

        if (name == "score")
            t.score = value;
        else
            t.stats.emplace_back(name, value);
    }
}

void Translator::OnTeam(const std::vector<std::string>& f)
{
    if (m_game && !Field(f, 1).empty())
        m_game->teamScores[Field(f, 1)] = Number(Field(f, 2));
}

// The totals and the standings, worked out as the other LANCommander server plugins do: in a
// team game the teams are ranked by score and each player takes their team's place; otherwise
// the players are ranked by score. A player who wasn't there at the end did not finish.
void Translator::OnEnd(const std::vector<std::string>& f)
{
    if (!m_game)
        return;

    const std::string winner = Field(f, 3);

    Report([this, totals = m_game->totals, teams = m_game->teamScores, winner](MatchHandle match) {
        for (const auto& [key, t] : totals)
        {
            m_reporter.SetStatistic(match, key, "", "score", t.score);

            for (const auto& [stat, value] : t.stats)
                m_reporter.SetStatistic(match, key, "", stat, value);
        }

        if (!teams.empty())
        {
            std::map<std::string, int> rank;

            for (const auto& [team, score] : teams)
            {
                int r = 1;

                for (const auto& [other, otherScore] : teams)
                {
                    if (other != team && (otherScore > score || (otherScore == score && other == winner)))
                        ++r;
                }

                // The game's own winner, when the scores alone don't say (a tiebreak)
                if (team == winner)
                    r = 1;

                rank[team] = r;
                m_reporter.SetStatistic(match, "", team, "score", score);
                m_reporter.SetResult(match, {"", team, r, r == 1 ? ResultStatus::Finished : ResultStatus::Defeated, score});
            }

            for (const auto& [key, t] : totals)
            {
                const auto it = rank.find(t.team);

                if (it == rank.end())
                    continue;

                const ResultStatus status = !t.present ? ResultStatus::DidNotFinish
                    : it->second == 1 ? ResultStatus::Finished : ResultStatus::Defeated;
                m_reporter.SetResult(match, {key, t.team, it->second, status, t.score});
            }
        }
        else
        {
            for (const auto& [key, t] : totals)
            {
                int r = 1;

                for (const auto& [otherKey, other] : totals)
                {
                    if (other.score > t.score)
                        ++r;
                }

                m_reporter.SetResult(match, {key, "", r,
                    t.present ? ResultStatus::Finished : ResultStatus::DidNotFinish, t.score});
            }
        }
    });

    Report([this, t = Time(f, 1)](MatchHandle match) {
        m_reporter.Event(match, "game_end", t, "", "", std::string());
    });

    EndGame(Field(f, 2).empty() ? "game_over" : Field(f, 2), false);
}

void Translator::EndGame(const std::string& reason, bool abandoned)
{
    if (!m_game)
        return;

    if (m_game->recording)
    {
        m_reporter.End(m_game->match, reason, abandoned);

        if (log)
            log("game " + m_game->id + " ended (" + reason + (abandoned ? ", abandoned" : "") + ")");
    }
    else if (log)
    {
        log("game " + m_game->id + " not reported: it never had " + std::to_string(m_settings.minPlayers) +
            " human players");
    }

    m_game.reset();
}

void Translator::Report(std::function<void(MatchHandle)> call)
{
    if (!m_game)
        return;

    if (m_game->recording)
        call(m_game->match);
    else
        m_game->held.push_back(std::move(call));
}

void Translator::NoteHuman(const std::string& key)
{
    if (!m_game)
        return;

    Game& game = *m_game;

    if (!key.empty())
        game.humans.insert(key);

    if (game.recording || static_cast<int>(game.humans.size()) < m_settings.minPlayers)
        return;

    game.match = m_reporter.Start(game.info);

    if (!game.match)
    {
        if (log)
            log("the Interposer refused game " + game.id);
        return;
    }

    game.recording = true;

    if (log)
        log("reporting game " + game.id);

    for (auto& call : game.held)
        call(game.match);

    game.held.clear();
}

std::string Translator::Recorded(const std::string& key) const
{
    if (key.empty() || (IsBot(key) && !m_settings.recordBots))
        return std::string();
    return key;
}

void Translator::Shutdown(unsigned timeoutMs)
{
    if (!m_game)
        return;

    const MatchHandle match = m_game->recording ? m_game->match : 0;
    EndGame("server_shutdown", true);

    if (match)
        m_reporter.Flush(match, timeoutMs);
}

} // namespace utstats
