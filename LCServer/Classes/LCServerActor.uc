//=============================================================================
// LCServerActor: LANCommander's server-side tools for UT2004. Add it to
// [Engine.GameEngine] ServerActors. It is never sent to clients.
//
//   - A rotation that mixes game types: each entry is a travel URL such as
//     "BR-Anubis?Game=XGame.xBombingRun?GoalScore=15?TimeLimit=15". When a
//     game ends, the server travels to the entry after the current one
//   - Skill-based team balancing when a team game's match starts, from the
//     ratings LCSkill keeps (System/LCSkill.ini)
//   - A limit on overtime in team games that can tie (CTF, Bombing Run):
//     once it runs out, the team with the most points between its players wins
//   - LANCommander match statistics: LCGameStats reports every game to the
//     image's ut2004-stats-bridge over TCP
//=============================================================================
class LCServerActor extends Info
	config;

var config bool          bMatchStats;
var config string        StatsHost;
var config int           StatsPort;

var config bool          bRotation;
var config array<string> MapRotation;

var config bool          bBalanceTeams;
var config int           BalanceMinPlayers;

var config int           MaxOvertimeMinutes;

// The rotation entry being played; the class default survives map changes
var int RotationIndex;

var LCStatsClient Client;
var LCGameStats   Stats;
var LCGameRules   Rules;
var LCSkill       Skill;

var bool  bAnnouncedNext;
var bool  bTravelling;
var bool  bTiebreakDone;
var float OvertimeSeconds;

event PostBeginPlay()
{
	Super.PostBeginPlay();

	if (Level.Game == None)
		return;

	Skill = new class'LCSkill';

	Rules = Spawn(class'LCGameRules');
	Rules.Master = self;
	if (Level.Game.GameRulesModifiers == None)
		Level.Game.GameRulesModifiers = Rules;
	else
		Level.Game.GameRulesModifiers.AddGameRules(Rules);

	if (bMatchStats)
	{
		Client = Spawn(class'LCStatsClient');
		Client.Setup(StatsHost, StatsPort);
	}

	// The game's events come to LCGameStats; it reports them when there is a
	// client, and keeps the scores for the skill ratings either way
	if (Level.Game.GameStats != None)
	{
		log("LCServer: replacing" @ Level.Game.GameStats.Class @ "with LCGameStats");
		Level.Game.GameStats.Destroy();
	}
	Stats = Spawn(class'LCGameStats');
	Stats.Master = self;
	Stats.Client = Client;
	if (Client != None)
		Client.Stats = Stats;
	Level.Game.GameStats = Stats;
	Stats.NewGame();

	log("LCServer: match statistics" @ bMatchStats $ ", rotation" @ bRotation @ "(" $ MapRotation.Length @ "maps), team balancing" @ bBalanceTeams $ ", overtime limit" @ MaxOvertimeMinutes @ "min");

	SetTimer(1.0, true);
}

event Timer()
{
	if (Stats != None && !Stats.bDeleteMe)
		Stats.Poll();

	CheckOvertime();

	if (Level.Game.bGameEnded && !bAnnouncedNext)
	{
		bAnnouncedNext = true;
		AnnounceNext();
	}
}

// ---------------------------------------------------------------------------
// Rotation
// ---------------------------------------------------------------------------

function string CurrentMapName()
{
	local string S;

	S = string(Level);
	if (InStr(S, ".") >= 0)
		S = Left(S, InStr(S, "."));
	return S;
}

function string EntryMap(string Entry)
{
	if (InStr(Entry, "?") >= 0)
		return Left(Entry, InStr(Entry, "?"));
	return Entry;
}

function string EntryGame(string Entry)
{
	if (InStr(Entry, "?") < 0)
		return "";
	return Level.Game.ParseOption(Mid(Entry, InStr(Entry, "?")), "Game");
}

function bool EntryMatches(string Entry, string MapName, string GameClass)
{
	local string G;

	if (!(EntryMap(Entry) ~= MapName))
		return false;
	G = EntryGame(Entry);
	return G == "" || G ~= GameClass;
}

function int CurrentIndex()
{
	local string MapName, GameClass;
	local int i;

	MapName = CurrentMapName();
	GameClass = string(Level.Game.Class);

	i = class'LCServerActor'.default.RotationIndex;
	if (i >= 0 && i < MapRotation.Length && EntryMatches(MapRotation[i], MapName, GameClass))
		return i;

	for (i = 0; i < MapRotation.Length; i++)
		if (EntryMatches(MapRotation[i], MapName, GameClass))
			return i;

	return -1;
}

function int NextIndex()
{
	return (CurrentIndex() + 1) % MapRotation.Length;
}

// Called by LCGameRules when the game wants to move on; true when it travels
function bool TravelToNext()
{
	local int i;

	if (!bRotation || MapRotation.Length == 0)
		return false;
	if (bTravelling)
		return true;

	i = NextIndex();
	class'LCServerActor'.default.RotationIndex = i;
	bTravelling = true;

	log("LCServer: rotation ->" @ MapRotation[i]);
	Level.ServerTravel(MapRotation[i], false);
	return true;
}

function string GameTitle(string GameClass)
{
	if (GameClass ~= "XGame.xCTFGame")              return "Capture the Flag";
	if (GameClass ~= "XGame.xBombingRun")           return "Bombing Run";
	if (GameClass ~= "Onslaught.ONSOnslaughtGame")  return "Onslaught";
	if (GameClass ~= "XGame.xDeathMatch")           return "Deathmatch";
	if (GameClass ~= "XGame.xTeamGame")             return "Team Deathmatch";
	if (GameClass ~= "XGame.xDoubleDom")            return "Double Domination";
	if (GameClass ~= "UT2k4Assault.ASGameInfo")     return "Assault";
	if (GameClass ~= "XGame.xVehicleCTFGame")       return "Vehicle CTF";
	return GameClass;
}

function AnnounceNext()
{
	local string Entry, G;

	if (!bRotation || MapRotation.Length == 0)
		return;

	Entry = MapRotation[NextIndex()];
	G = EntryGame(Entry);
	if (G == "")
		G = string(Level.Game.Class);

	Level.Game.Broadcast(self, "Next map:" @ EntryMap(Entry) @ "(" $ GameTitle(G) $ ")");
}

// ---------------------------------------------------------------------------
// Team balancing
// ---------------------------------------------------------------------------

// Called by LCGameStats.StartGame, before anyone has spawned
function BalanceTeams()
{
	local TeamGame TG;
	local Controller C, TmpC;
	local array<Controller> Humans;
	local array<float> Ratings;
	local int i, j, T, Cap, Moved;
	local int Count[2];
	local float Sum[2], TmpR;

	TG = TeamGame(Level.Game);
	if (!bBalanceTeams || TG == None || Skill == None)
		return;

	for (C = Level.ControllerList; C != None; C = C.NextController)
	{
		if (PlayerController(C) == None || C.PlayerReplicationInfo == None)
			continue;
		if (C.PlayerReplicationInfo.bOnlySpectator || C.PlayerReplicationInfo.Team == None)
			continue;

		Humans[Humans.Length] = C;
		Ratings[Ratings.Length] = Skill.GetRating(C.PlayerReplicationInfo.PlayerName);
	}

	if (Humans.Length < Max(2, BalanceMinPlayers))
		return;

	// Best first
	for (i = 1; i < Humans.Length; i++)
	{
		for (j = i; j > 0 && Ratings[j] > Ratings[j - 1]; j--)
		{
			TmpC = Humans[j];   Humans[j] = Humans[j - 1];   Humans[j - 1] = TmpC;
			TmpR = Ratings[j];  Ratings[j] = Ratings[j - 1]; Ratings[j - 1] = TmpR;
		}
	}

	// Each player, best first, goes to the weaker team that still has room
	Cap = (Humans.Length + 1) / 2;
	for (i = 0; i < Humans.Length; i++)
	{
		if (Count[0] >= Cap)
			T = 1;
		else if (Count[1] >= Cap)
			T = 0;
		else if (Sum[0] < Sum[1])
			T = 0;
		else if (Sum[1] < Sum[0])
			T = 1;
		else if (Count[0] <= Count[1])
			T = 0;
		else
			T = 1;

		Count[T]++;
		Sum[T] += Ratings[i];

		if (Humans[i].PlayerReplicationInfo.Team.TeamIndex != T)
		{
			MoveToTeam(TG, Humans[i], T);
			Moved++;
		}
	}

	log("LCServer: balanced" @ Humans.Length @ "players by skill (red" @ Sum[0] $ ", blue" @ Sum[1] $ ")," @ Moved @ "moved");
	if (Moved > 0)
		Level.Game.Broadcast(self, "Teams have been balanced by skill");
}

// Moves a player without TeamGame.ChangeTeam, which would send them to the
// smaller team while the others are still being placed
function MoveToTeam(TeamGame TG, Controller C, int T)
{
	C.StartSpot = None;
	if (C.PlayerReplicationInfo.Team != None)
		C.PlayerReplicationInfo.Team.RemoveFromTeam(C);
	TG.Teams[T].AddToTeam(C);
}

// ---------------------------------------------------------------------------
// Overtime limit
// ---------------------------------------------------------------------------

function CheckOvertime()
{
	local TeamGame TG;
	local int W;

	TG = TeamGame(Level.Game);
	if (MaxOvertimeMinutes <= 0 || TG == None || bTiebreakDone || Level.Game.bGameEnded || !Level.Game.bOverTime)
		return;

	// Onslaught's overtime drains the cores, so it ends by itself
	if (Level.Game.IsA('ONSOnslaughtGame'))
		return;

	OvertimeSeconds += 1.0;

	if (MaxOvertimeMinutes > 1 && OvertimeSeconds == (MaxOvertimeMinutes - 1) * 60)
		Level.Game.Broadcast(self, "One minute of overtime left, then the team with the most points wins");

	if (OvertimeSeconds < MaxOvertimeMinutes * 60)
		return;

	W = TiebreakWinner(TG);
	if (W < 0)
		return;   // dead level: play on until someone scores or pulls ahead

	bTiebreakDone = true;
	if (Stats != None && !Stats.bDeleteMe)
		Stats.Tiebreak(W);

	Level.Game.Broadcast(self, "Overtime limit reached:" @ TG.Teams[W].GetHumanReadableName() @ "wins on points");
	log("LCServer: overtime limit reached, team" @ W @ "wins on points");

	TG.Teams[W].Score += 1;
	TG.EndGame(None, "TimeLimit");
}

function int TiebreakWinner(TeamGame TG)
{
	local GameReplicationInfo GRI;
	local PlayerReplicationInfo PRI;
	local float Points[2];
	local int i;

	GRI = Level.Game.GameReplicationInfo;
	for (i = 0; i < GRI.PRIArray.Length; i++)
	{
		PRI = GRI.PRIArray[i];
		if (PRI == None || PRI.bOnlySpectator || PRI.Team == None || PRI.Team.TeamIndex > 1)
			continue;
		Points[PRI.Team.TeamIndex] += PRI.Score;
	}

	if (Points[0] > Points[1])
		return 0;
	if (Points[1] > Points[0])
		return 1;
	return -1;
}

defaultproperties
{
	bMatchStats=False
	StatsHost="127.0.0.1"
	StatsPort=7790
	bRotation=False
	bBalanceTeams=True
	BalanceMinPlayers=4
	MaxOvertimeMinutes=0
	RotationIndex=-1
	RemoteRole=ROLE_None
}
