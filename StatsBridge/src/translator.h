// LCServer's stats lines -> LANCommander matches.
//
// The UT2004 server's LCServer package (LCGameStats) sends one line per thing that happened,
// tab-separated, with times in milliseconds of game time since the match started:
//
//   HELLO  1  <server name>
//   START  <t>  <match id>  <map>  <mode>  <map title>  k=v...   the game's settings
//   JOIN   <t>  <key>  <name>  <team>                            also a rename or team change
//   LEAVE  <t>  <key>
//   EVENT  <t>  <type>  <actor key>  <subject key>  k=v...       the event's payload
//   PLAYER <key>  <team>  <present 0|1>  k=v...                  a player's totals, at the end
//   TEAM   <team>  <score>                                       a team's score, at the end
//   END    <t>  <reason>  <winning team>
//
// Each game (one map played) is one match, keyed by its match id. A START with the id of the
// open match carries on with it (LCServer reconnected); one with another id ends the open match
// as abandoned (the map was changed before the game ended).
//
// Player keys are "name:<name>" for players and "bot:<name>" for bots. A game is only reported
// once enough human players have been in it (MinPlayers); until then its calls are held, and a
// game that never gets there is dropped, so an empty server cycling through its rotation records
// nothing.

#pragma once

#include "reporter.h"

#include <functional>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace utstats
{

struct TranslatorSettings
{
    int  minPlayers = 1;     // human players in a game before it is reported
    bool recordBots = true;
};

class Translator
{
public:
    Translator(Reporter& reporter, TranslatorSettings settings);

    // One line from LCServer, as received (Latin-1, without the line break).
    void OnLine(const std::string& line);

    // The server is going away: end the open game, if any, as abandoned, and wait up to
    // timeoutMs for delivery.
    void Shutdown(unsigned timeoutMs);

    // The server name from HELLO, once known; for the reporter name.
    std::function<void(const std::string& serverName)> onServerName;

    // Status lines for the console.
    std::function<void(const std::string& line)> log;

private:
    struct Totals
    {
        std::string team;
        bool        present = false;
        double      score = 0;
        std::vector<std::pair<std::string, double>> stats;
    };

    struct Game
    {
        std::string id;
        MatchInfo   info;
        MatchHandle match = 0;
        bool        recording = false;
        std::vector<std::function<void(MatchHandle)>> held;
        std::set<std::string> humans;
        std::map<std::string, Totals> totals;
        std::map<std::string, double> teamScores;
    };

    void OnStart(const std::vector<std::string>& f);
    void OnJoin(const std::vector<std::string>& f);
    void OnLeave(const std::vector<std::string>& f);
    void OnEvent(const std::vector<std::string>& f);
    void OnPlayer(const std::vector<std::string>& f);
    void OnTeam(const std::vector<std::string>& f);
    void OnEnd(const std::vector<std::string>& f);

    void EndGame(const std::string& reason, bool abandoned);
    void Report(std::function<void(MatchHandle)> call);
    void NoteHuman(const std::string& key);
    std::string Recorded(const std::string& key) const;   // "" for bots when they aren't recorded

    Reporter&          m_reporter;
    TranslatorSettings m_settings;

    std::string         m_serverName;
    std::optional<Game> m_game;
};

// "a=1", "b=x" ... -> {"a":1,"b":"x"}: numbers and true/false keep their type
std::string PayloadJson(const std::vector<std::string>& fields, std::size_t first);

// Latin-1 -> UTF-8
std::string FromLatin1(const std::string& text);

} // namespace utstats
