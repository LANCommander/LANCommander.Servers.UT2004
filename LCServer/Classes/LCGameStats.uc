//=============================================================================
// LCGameStats: takes the game's stats events (GameInfo.GameStats) and turns
// them into lines for ut2004-stats-bridge, which reports the game to
// LANCommander as a match. Unlike the stock GameStats, it counts bots, and
// it keys players by name: "name:<name>" for players and "bot:<name>" for bots.
//
// The lines are tab-separated. Times are milliseconds of game time since the
// match started, and k=v fields become the event's JSON payload:
//
//   HELLO  1  <server name>
//   START  <t>  <match id>  <map>  <mode>  <map title>  k=v...
//   JOIN   <t>  <key>  <name>  <team>            (also a rename or team change)
//   LEAVE  <t>  <key>
//   EVENT  <t>  <type>  <actor key>  <subject key>  k=v...
//   PLAYER <key>  <team>  <present 0|1>  k=v...  (end-of-game totals)
//   TEAM   <team>  <score>
//   END    <t>  <reason>  <winning team>
//
// It also feeds LCSkill: after a team game, each human player's rating moves
// towards their place on the scoreboard.
//=============================================================================
class LCGameStats extends GameStats;

struct PlayerEntry
{
	var PlayerReplicationInfo PRI;
	var string Key;
	var string Name;
	var string Team;
	var bool   bBot;
	var bool   bPresent;
	var float  JoinTime;
	var float  PlayTime;
	var float  Score;
	var int    Kills;
	var int    Deaths;
	var int    Suicides;
	var int    TeamKills;
};

struct ExtraStat
{
	var int    Player;
	var string Name;
	var float  Value;
};

var LCServerActor Master;
var LCStatsClient Client;

var array<PlayerEntry> Players;
var array<ExtraStat>   Extra;

var string MatchId;
var string StartLine;
var bool   bNewGame;
var bool   bStarted;
var bool   bEnded;
var float  StartTime;
var int    TiebreakTeam;

// No local log file: everything goes to the bridge
function Init();
function Shutdown();

function string Clean(coerce string S)
{
	ReplaceText(S, Chr(9), " ");
	ReplaceText(S, Chr(10), " ");
	ReplaceText(S, Chr(13), " ");
	return S;
}

function Send(string Line)
{
	if (Client != None && !Client.bDeleteMe)
		Client.SendLine(Line);
}

function int GameTime()
{
	if (!bStarted)
		return 0;
	return int((Level.TimeSeconds - StartTime) * 1000.0);
}

function string Num(float F)
{
	if (float(int(F)) == F)
		return string(int(F));
	return string(F);
}

function string Two(int N)
{
	return Right("0" $ N, 2);
}

function string ModeName()
{
	local string G;

	G = string(Level.Game.Class);
	if (G ~= "XGame.xDeathMatch")                 return "deathmatch";
	if (G ~= "XGame.xTeamGame")                   return "team_deathmatch";
	if (G ~= "XGame.xCTFGame")                    return "ctf";
	if (G ~= "XGame.xVehicleCTFGame")             return "vehicle_ctf";
	if (G ~= "XGame.xBombingRun")                 return "bombing_run";
	if (G ~= "XGame.xDoubleDom")                  return "double_domination";
	if (G ~= "Onslaught.ONSOnslaughtGame")        return "onslaught";
	if (G ~= "UT2k4Assault.ASGameInfo")           return "assault";
	if (G ~= "SkaarjPack.Invasion")               return "invasion";
	if (G ~= "BonusPack.xLastManStandingGame")    return "last_man_standing";
	if (G ~= "BonusPack.xMutantGame")             return "mutant";
	return Locs(string(Level.Game.Class.Name));
}

function string TeamOf(PlayerReplicationInfo PRI)
{
	if (PRI == None || PRI.Team == None)
		return "";
	if (PRI.Team.TeamIndex == 0)
		return "red";
	if (PRI.Team.TeamIndex == 1)
		return "blue";
	return "team" $ PRI.Team.TeamIndex;
}

function string TeamName(int Index)
{
	if (Index == 0)
		return "red";
	if (Index == 1)
		return "blue";
	return "team" $ Index;
}

// Lowercase, with anything but letters and digits turned into underscores
function string EventName(string S)
{
	local string Result, C;
	local int i;

	S = Locs(S);
	for (i = 0; i < Len(S); i++)
	{
		C = Mid(S, i, 1);
		if ((C >= "a" && C <= "z") || (C >= "0" && C <= "9"))
			Result = Result $ C;
		else if (Right(Result, 1) != "_")
			Result = Result $ "_";
	}
	return Result;
}

// ---------------------------------------------------------------------------
// Players
// ---------------------------------------------------------------------------

function bool InPRIArray(PlayerReplicationInfo PRI)
{
	local int i;

	for (i = 0; i < GRI.PRIArray.Length; i++)
		if (GRI.PRIArray[i] == PRI)
			return true;
	return false;
}

function string JoinLine(int i)
{
	return "JOIN" $ Tab $ GameTime() $ Tab $ Players[i].Key $ Tab $ Clean(Players[i].Name) $ Tab $ Players[i].Team;
}

// The entry of a player, added (and announced) if new; -1 for spectators
function int Track(PlayerReplicationInfo PRI)
{
	local int i;
	local string Key;

	if (PRI == None || PRI.bOnlySpectator || PRI.bDeleteMe)
		return -1;

	for (i = 0; i < Players.Length; i++)
		if (Players[i].PRI == PRI)
			return i;

	if (PRI.bBot)
		Key = "bot:" $ Clean(PRI.PlayerName);
	else
		Key = "name:" $ Clean(PRI.PlayerName);

	// Back after leaving: the same entry. Someone else with a name in use: a new key
	for (i = 0; i < Players.Length; i++)
	{
		if (Players[i].Key != Key)
			continue;
		if (!Players[i].bPresent)
			break;
		Key = Key $ "#" $ (Players.Length + 1);
		i = Players.Length;
		break;
	}

	if (i == Players.Length)
	{
		Players.Length = i + 1;
		Players[i].Key = Key;
		Players[i].bBot = PRI.bBot;
	}

	Players[i].PRI = PRI;
	Players[i].Name = PRI.PlayerName;
	Players[i].Team = TeamOf(PRI);
	Players[i].bPresent = true;
	Players[i].JoinTime = Level.TimeSeconds;
	Send(JoinLine(i));
	return i;
}

// Once a second: who joined, left, renamed or changed team
function Poll()
{
	local int i;
	local PlayerReplicationInfo PRI;
	local string Team;

	if (bEnded)
		return;
	if (GRI == None)
		GRI = Level.Game.GameReplicationInfo;
	if (GRI == None)
		return;

	for (i = 0; i < GRI.PRIArray.Length; i++)
		Track(GRI.PRIArray[i]);

	for (i = 0; i < Players.Length; i++)
	{
		if (!Players[i].bPresent)
			continue;

		PRI = Players[i].PRI;
		if (PRI == None || PRI.bDeleteMe || PRI.bOnlySpectator || !InPRIArray(PRI))
		{
			Players[i].bPresent = false;
			Players[i].PlayTime += Level.TimeSeconds - FMax(Players[i].JoinTime, StartTime);
			Players[i].PRI = None;
			Send("LEAVE" $ Tab $ GameTime() $ Tab $ Players[i].Key);
			continue;
		}

		Players[i].Score = PRI.Score;

		Team = TeamOf(PRI);
		if (PRI.PlayerName != Players[i].Name || Team != Players[i].Team)
		{
			if (Team != Players[i].Team && Players[i].Team != "" && bStarted)
				Send("EVENT" $ Tab $ GameTime() $ Tab $ "team_change" $ Tab $ Players[i].Key $ Tab $ Tab $ "from=" $ Players[i].Team $ Tab $ "to=" $ Team);
			Players[i].Name = PRI.PlayerName;
			Players[i].Team = Team;
			Send(JoinLine(i));
		}
	}
}

function string KeyOf(PlayerReplicationInfo PRI)
{
	local int i;

	i = Track(PRI);
	if (i < 0)
		return "";
	return Players[i].Key;
}

function AddExtra(int Player, string Name, float Value)
{
	local int i;

	if (Player < 0)
		return;
	for (i = 0; i < Extra.Length; i++)
	{
		if (Extra[i].Player == Player && Extra[i].Name == Name)
		{
			Extra[i].Value += Value;
			return;
		}
	}
	Extra.Length = i + 1;
	Extra[i].Player = Player;
	Extra[i].Name = Name;
	Extra[i].Value = Value;
}

// ---------------------------------------------------------------------------
// The game
// ---------------------------------------------------------------------------

function NewGame()
{
	local string S;

	if (bNewGame)
		return;
	bNewGame = true;

	GRI = Level.Game.GameReplicationInfo;
	MatchId = "ut2004:" $ Level.Year $ Two(Level.Month) $ Two(Level.Day) $ "T" $ Two(Level.Hour) $ Two(Level.Minute) $ Two(Level.Second) $ ":" $ MapName();

	S = "START" $ Tab $ "0" $ Tab $ MatchId $ Tab $ MapName() $ Tab $ ModeName() $ Tab $ Clean(Level.Title);
	S = S $ Tab $ "game_class=" $ string(Level.Game.Class);
	S = S $ Tab $ "goal_score=" $ Level.Game.GoalScore;
	S = S $ Tab $ "time_limit_ms=" $ (Level.Game.TimeLimit * 60000);
	S = S $ Tab $ "max_players=" $ Level.Game.MaxPlayers;
	if (TeamGame(Level.Game) != None)
		S = S $ Tab $ "friendly_fire=" $ Num(TeamGame(Level.Game).FriendlyFireScale);
	if (Master != None && Master.MaxOvertimeMinutes > 0 && TeamGame(Level.Game) != None)
		S = S $ Tab $ "max_overtime_ms=" $ (Master.MaxOvertimeMinutes * 60000);
	StartLine = S;

	Send("HELLO" $ Tab $ "1" $ Tab $ Clean(GRI.ServerName));
	Send(StartLine);
	Poll();
}

// The game's own call; NewGame already ran
function ServerInfo();

// After a reconnect: the game's start and roster go out again, before
// whatever was queued meanwhile
function Resync()
{
	local array<string> Lines;
	local int i;

	if (!bNewGame || bEnded)
		return;

	Lines[Lines.Length] = "HELLO" $ Tab $ "1" $ Tab $ Clean(GRI.ServerName);
	Lines[Lines.Length] = StartLine;
	for (i = 0; i < Players.Length; i++)
		if (Players[i].bPresent)
			Lines[Lines.Length] = JoinLine(i);
	Client.PrependLines(Lines);
}

function StartGame()
{
	local int i;

	if (bStarted)
		return;

	if (Master != None)
		Master.BalanceTeams();

	bStarted = true;
	StartTime = Level.TimeSeconds;

	Poll();
	for (i = 0; i < Players.Length; i++)
		if (Players[i].bPresent)
			Players[i].JoinTime = StartTime;

	Send("EVENT" $ Tab $ "0" $ Tab $ "match_start" $ Tab $ Tab);
}

function Tiebreak(int Team)
{
	TiebreakTeam = Team;
	Send("EVENT" $ Tab $ GameTime() $ Tab $ "overtime_limit" $ Tab $ Tab $ Tab $ "winner=" $ TeamName(Team) $ Tab $ "tiebreak=player_points");
}

function EndGame(string Reason)
{
	local TeamGame TG;
	local string S, Winner;
	local int i, j;
	local float Score;

	if (bEnded)
		return;

	Poll();
	bEnded = true;

	for (i = 0; i < Players.Length; i++)
	{
		if (Players[i].bPresent)
		{
			Players[i].PlayTime += Level.TimeSeconds - FMax(Players[i].JoinTime, StartTime);
			if (Players[i].PRI != None)
				Players[i].Score = Players[i].PRI.Score;
		}

		S = "PLAYER" $ Tab $ Players[i].Key $ Tab $ Players[i].Team $ Tab;
		if (Players[i].bPresent)
			S = S $ "1";
		else
			S = S $ "0";
		S = S $ Tab $ "score=" $ Num(Players[i].Score);
		S = S $ Tab $ "kills=" $ Players[i].Kills;
		S = S $ Tab $ "deaths=" $ Players[i].Deaths;
		S = S $ Tab $ "suicides=" $ Players[i].Suicides;
		S = S $ Tab $ "team_kills=" $ Players[i].TeamKills;
		S = S $ Tab $ "time_played_ms=" $ int(FMax(Players[i].PlayTime, 0) * 1000.0);
		for (j = 0; j < Extra.Length; j++)
			if (Extra[j].Player == i)
				S = S $ Tab $ Extra[j].Name $ "=" $ Num(Extra[j].Value);
		Send(S);
	}

	TG = TeamGame(Level.Game);
	if (TG != None)
	{
		for (i = 0; i < 2; i++)
		{
			Score = TG.Teams[i].Score;
			if (i == TiebreakTeam)
				Score -= 1;   // the point LCServerActor gave the tiebreak's winner
			Send("TEAM" $ Tab $ TeamName(i) $ Tab $ Num(Score));
		}
		if (TeamInfo(GRI.Winner) != None)
			Winner = TeamName(TeamInfo(GRI.Winner).TeamIndex);
	}

	if (TiebreakTeam >= 0)
		Reason = "overtime_tiebreak";
	Send("END" $ Tab $ GameTime() $ Tab $ EventName(Reason) $ Tab $ Winner);

	UpdateRatings();
}

// Each human player's place on the scoreboard, among everyone who played at
// least half the game (or 3 minutes) and was there at the end
function UpdateRatings()
{
	local array<int> Order;
	local int i, j, Tmp, Humans;
	local float MinTime;

	if (Master == None || Master.Skill == None || TeamGame(Level.Game) == None)
		return;

	MinTime = FMin(180.0, (Level.TimeSeconds - StartTime) * 0.5);
	for (i = 0; i < Players.Length; i++)
	{
		if (!Players[i].bPresent || Players[i].PlayTime < MinTime || Players[i].Team == "")
			continue;
		Order[Order.Length] = i;
		if (!Players[i].bBot)
			Humans++;
	}

	if (Humans < 2 || Order.Length < 2)
		return;

	for (i = 1; i < Order.Length; i++)
	{
		for (j = i; j > 0 && Players[Order[j]].Score > Players[Order[j - 1]].Score; j--)
		{
			Tmp = Order[j];
			Order[j] = Order[j - 1];
			Order[j - 1] = Tmp;
		}
	}

	for (i = 0; i < Order.Length; i++)
		if (!Players[Order[i]].bBot)
			Master.Skill.Update(Players[Order[i]].Name, 1.0 - float(i) / float(Order.Length - 1));

	Master.Skill.SaveConfig();
}

// ---------------------------------------------------------------------------
// The game's events
// ---------------------------------------------------------------------------

function ConnectEvent(PlayerReplicationInfo Who)
{
	Track(Who);
}

function DisconnectEvent(PlayerReplicationInfo Who);

function KillEvent(string KillType, PlayerReplicationInfo Killer, PlayerReplicationInfo Victim, class<DamageType> Damage)
{
	local int K, V;
	local string S, Actor;

	if (bEnded || Victim == None)
		return;

	V = Track(Victim);
	if (V < 0)
		return;
	K = -1;
	if (Killer != None)
		K = Track(Killer);

	Players[V].Deaths++;

	if (Damage != None)
	{
		S = S $ Tab $ "damage_type=" $ Damage.Name;
		if (class<WeaponDamageType>(Damage) != None && class<WeaponDamageType>(Damage).default.WeaponClass != None)
			S = S $ Tab $ "weapon=" $ class<WeaponDamageType>(Damage).default.WeaponClass.Name;
		else if (class<VehicleDamageType>(Damage) != None && class<VehicleDamageType>(Damage).default.VehicleClass != None)
			S = S $ Tab $ "vehicle=" $ class<VehicleDamageType>(Damage).default.VehicleClass.Name;
	}

	if (K < 0 || K == V)
	{
		Players[V].Suicides++;
		Actor = Players[V].Key;
		S = S $ Tab $ "suicide=true";
		if (K < 0)
			S = S $ Tab $ "world=true";
	}
	else
	{
		Actor = Players[K].Key;
		if (KillType == "TK")
		{
			Players[K].TeamKills++;
			S = S $ Tab $ "teamkill=true";
		}
		else
			Players[K].Kills++;
	}

	Send("EVENT" $ Tab $ GameTime() $ Tab $ "kill" $ Tab $ Actor $ Tab $ Players[V].Key $ S);
}

function ScoreEvent(PlayerReplicationInfo Who, float Points, string Desc)
{
	local int P;
	local string Type, S;

	if (bEnded || Who == None)
		return;

	P = Track(Who);
	if (P < 0)
		return;

	Desc = Locs(Desc);

	// Frags and node healing are too frequent to be events: totals only
	if (Desc == "frag" || Desc == "self_frag" || Desc == "team_frag")
		return;
	if (Desc == "heal_powernode")
	{
		AddExtra(P, "node_heal_points", Points);
		return;
	}

	switch (Desc)
	{
		case "flag_cap_final":     AddExtra(P, "flag_captures", 1);   break;
		case "flag_cap_assist":    AddExtra(P, "flag_assists", 1);    break;
		case "flag_cap_1st_touch": AddExtra(P, "flag_first_touches", 1); break;
		case "flag_ret_friendly":
		case "flag_ret_enemy":     AddExtra(P, "flag_returns", 1);    break;
		case "flag_denial":        AddExtra(P, "flag_denials", 1);    break;
		case "critical_frag":      AddExtra(P, "carrier_kills", 1);   break;
		case "ball_cap_final":     AddExtra(P, "bomb_runs", 1);       Type = "bomb_scored"; S = Tab $ "method=carried"; break;
		case "ball_thrown_final":  AddExtra(P, "bomb_throws", 1);     Type = "bomb_scored"; S = Tab $ "method=thrown"; break;
		case "ball_score_assist":  AddExtra(P, "bomb_assists", 1);    break;
		case "dom_score":          AddExtra(P, "dom_scores", 1);      break;
		case "objective_completed":
		case "objectivescore":     AddExtra(P, "objectives", 1);      Type = "objective_completed"; break;
	}

	// Onslaught: "<team>_powernode_constructed" and the like
	if (InStr(Desc, "constructed") >= 0)
	{
		AddExtra(P, "nodes_built", 1);
		Type = "node_built";
	}

	if (Type == "")
		return;
	Send("EVENT" $ Tab $ GameTime() $ Tab $ Type $ Tab $ Players[P].Key $ Tab $ Tab $ "points=" $ Num(Points) $ S);
}

// Onslaught power nodes and cores (LCGameRules)
function ObjectiveScored(PlayerReplicationInfo Scorer, int Score)
{
	local int P;

	if (bEnded || Score != 0)
		return;

	P = Track(Scorer);
	AddExtra(P, "nodes_destroyed", 1);
	if (P >= 0)
		Send("EVENT" $ Tab $ GameTime() $ Tab $ "node_destroyed" $ Tab $ Players[P].Key $ Tab);
	else
		Send("EVENT" $ Tab $ GameTime() $ Tab $ "node_destroyed" $ Tab $ Tab);
}

function TeamScoreEvent(int Team, float Points, string Desc)
{
	if (bEnded)
		return;

	Desc = Locs(Desc);
	if (Desc == "tdm_frag" || Desc == "team_frag")
		return;

	Send("EVENT" $ Tab $ GameTime() $ Tab $ "team_score" $ Tab $ Tab $ Tab $ "team=" $ TeamName(Team) $ Tab $ "points=" $ Num(Points) $ Tab $ "reason=" $ EventName(Desc));
}

function GameEvent(string GEvent, string Desc, PlayerReplicationInfo Who)
{
	local string Actor, S;

	if (bEnded)
		return;

	// The roster is polled
	if (GEvent ~= "NameChange" || GEvent ~= "TeamChange")
		return;

	if (Who != None)
		Actor = KeyOf(Who);

	// flag_*: Desc is the flag's team
	if (Left(GEvent, 5) ~= "flag_" && (Desc == "0" || Desc == "1"))
		S = Tab $ "flag_team=" $ TeamName(int(Desc));
	else if (Desc != "" && Desc != "255")   // bomb_*: 255, no team
		S = Tab $ "detail=" $ Clean(Desc);

	Send("EVENT" $ Tab $ GameTime() $ Tab $ EventName(GEvent) $ Tab $ Actor $ Tab $ S);
}

// first_blood, spree_<n>, multikill_<n>, and adrenaline combos (their class)
function SpecialEvent(PlayerReplicationInfo Who, string Desc)
{
	local int P;
	local string Type, S;

	if (bEnded || Who == None)
		return;

	P = Track(Who);
	if (P < 0)
		return;

	if (InStr(Desc, ".") >= 0)
	{
		Type = "combo";
		S = Tab $ "combo=" $ Mid(Desc, InStr(Desc, ".") + 1);
		AddExtra(P, "combos", 1);
	}
	else
	{
		Type = EventName(Desc);
		if (Left(Type, 6) == "spree_")
		{
			S = Tab $ "level=" $ Mid(Type, 6);
			Type = "spree";
		}
		else if (Left(Type, 10) == "multikill_")
		{
			S = Tab $ "level=" $ Mid(Type, 10);
			Type = "multikill";
			AddExtra(P, "multikills", 1);
		}
		else if (Type == "first_blood")
			AddExtra(P, "first_blood", 1);
	}

	Send("EVENT" $ Tab $ GameTime() $ Tab $ Type $ Tab $ Players[P].Key $ Tab $ S);
}

defaultproperties
{
	TiebreakTeam=-1
	RemoteRole=ROLE_None
}
