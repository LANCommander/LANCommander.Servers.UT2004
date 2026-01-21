# Server Options
This document outlines some common options available to Unreal Tournament 2004 servers. These options can be changed in `System/UT2004.ini`.

| Section            | Option                     | Description                                                                 | Example Value            |
|--------------------|----------------------------|-----------------------------------------------------------------------------|--------------------------|
| `[Engine.GameInfo]`| MaxPlayers                 | Maximum number of players allowed on the server                             | `16`                     |
|                    | GameDifficulty             | AI difficulty level (0–7)                                                    | `3`                      |
|                    | bAdminCanPause             | Allows admins to pause the game                                              | `True`                   |
|                    | bChangeLevels              | Allows automatic map changes                                                 | `True`                   |
|                    | bAllowBehindView           | Allows third-person (behind view)                                            | `False`                  |
|                    | GameSpeed                  | Overall game speed multiplier                                                | `1.0`                    |
|                    | MaxSpectators              | Maximum number of spectators                                                 | `2`                      |
|                    | bRestartLevel              | Restart map after match instead of switching                                 | `False`                  |
|                    | bWeaponStay                | Weapons remain after pickup                                                  | `True`                   |
|                    | bTeamScoreRounds           | Teams score per round instead of per match                                   | `False`                  |
|                    | bAllowPlayerLights         | Allows player dynamic lights                                                 | `False`                  |
|                    | bEnableStatLogging         | Enables stat logging                                                         | `True`                   |
|                    | bAllowPrivateChat          | Enables private chat                                                         | `True`                   |
|                    | bAllowWeaponThrowing       | Allows players to throw weapons                                              | `True`                   |
|                    | bTournament                | Enables tournament mode                                                      | `False`                  |
|                    | bPlayersMustBeReady        | Players must ready up before match starts                                    | `False`                  |
|                    | bForceRespawn              | Forces immediate respawn                                                     | `False`                  |
|                    | bNetReady                  | Requires network readiness                                                   | `True`                   |
|                    | TimeLimit                  | Time limit in minutes                                                        | `20`                     |
|                    | GoalScore                  | Score required to win                                                        | `0`                      |
|                    | MaxLives                   | Maximum lives per player (0 = unlimited)                                     | `0`                      |
|                    | AutoAim                    | Auto-aim assistance level                                                    | `0.93`                   |
|                    | FriendlyFireScale          | Friendly fire damage multiplier                                              | `0.0`                    |
|                    | Mutator                    | Comma-separated list of mutators                                             | `XGame.MutNoAdrenaline`  |
|                    | AccessControl              | Access control class                                                         | `Engine.AccessControl`  |
|                    | ServerName                 | Name shown in server browser                                                 | `My UT2004 Server`       |
|                    | AdminName                  | Administrator display name                                                   | `Admin`                  |
|                    | AdminEmail                 | Administrator contact email                                                  | `admin@example.com`      |
|                    | MOTDLine1                  | Message of the Day line 1                                                    | `Welcome to the server`  |
|                    | MOTDLine2                  | Message of the Day line 2                                                    | `Have fun!`              |
|                    | MOTDLine3                  | Message of the Day line 3                                                    | `No cheating`            |
|                    | MOTDLine4                  | Message of the Day line 4                                                    | `Be respectful`          |
| `[Engine.GameReplicationInfo]` | ServerRegion      | Server region code (0–7)                                                     | `0`                      |
|                    | ShortName                  | Short server name                                                            | `UT2004`                 |
|                    | bTeamGame                  | Indicates team-based game                                                    | `True`                   |
| `[Engine.AccessControl]` | AdminPassword         | Password for admin login                                                     | `changeme`               |
|                    | GamePassword               | Password required to join server                                             | `""`                     |
|                    | IPPolicies                 | IP allow/deny rules                                                          | `ACCEPT,*`               |
| `[IpDrv.UdpServerQuery]` | QueryPort            | Port used for server queries                                                 | `8076`                   |
| `[IpDrv.UdpGameSpyQuery]` | GameSpyPort         | GameSpy query port                                                           | `6500`                   |
| `[IpDrv.MasterServerLink]` | MasterServerAddress | Master server hostname                                                       | `ut2004master.epicgames.com` |
|                    | MasterServerPort           | Master server port                                                           | `28902`                  |
| `[Engine.DemoRecDriver]` | DemoSpectatorClass   | Demo spectator class                                                         | `UnrealGame.DemoSpectator` |
|                    | MaxFileSize                | Maximum demo file size (MB)                                                  | `1024`                   |
