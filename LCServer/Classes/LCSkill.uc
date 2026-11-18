//=============================================================================
// LCSkill: each player's skill rating, kept in System/LCSkill.ini by name.
//
// A rating runs from 0 (always last) to 1 (always first). After each team
// game, a player's rating moves towards where they finished on the
// scoreboard. New players start in the middle, at 0.5.
//=============================================================================
class LCSkill extends Object
	config(LCSkill);

struct SkillEntry
{
	var string Name;
	var float  Rating;
	var int    Games;
};

var config array<SkillEntry> Players;

function int Find(string PlayerName)
{
	local int i;

	PlayerName = Locs(PlayerName);
	for (i = 0; i < Players.Length; i++)
		if (Players[i].Name == PlayerName)
			return i;
	return -1;
}

function float GetRating(string PlayerName)
{
	local int i;

	i = Find(PlayerName);
	if (i < 0)
		return 0.5;
	return Players[i].Rating;
}

// Performance: 1 for the top of the scoreboard, 0 for the bottom
function Update(string PlayerName, float Performance)
{
	local int i;
	local float Weight;

	i = Find(PlayerName);
	if (i < 0)
	{
		i = Players.Length;
		Players.Length = i + 1;
		Players[i].Name = Locs(PlayerName);
		Players[i].Rating = 0.5;
		Players[i].Games = 0;
	}

	Weight = FMax(0.25, 1.0 / float(Players[i].Games + 2));
	Players[i].Rating = FClamp(Players[i].Rating + (Performance - Players[i].Rating) * Weight, 0.0, 1.0);
	Players[i].Games++;
}
