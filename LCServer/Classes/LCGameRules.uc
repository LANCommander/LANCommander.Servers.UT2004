//=============================================================================
// LCGameRules: hands the end of a game to LCServerActor's rotation, and
// Onslaught's power node destructions to LCGameStats.
//=============================================================================
class LCGameRules extends GameRules;

var LCServerActor Master;

function bool HandleRestartGame()
{
	if (Master != None && Master.TravelToNext())
		return true;
	return Super.HandleRestartGame();
}

function ScoreObjective(PlayerReplicationInfo Scorer, int Score)
{
	if (Master != None && Master.Stats != None && !Master.Stats.bDeleteMe)
		Master.Stats.ObjectiveScored(Scorer, Score);
	Super.ScoreObjective(Scorer, Score);
}

defaultproperties
{
	RemoteRole=ROLE_None
}
