#Requires -Modules Logging

# LANCommander's server-side package, LCServer (the image's /usr/local/share/ut2004/LCServer):
#
#   - UT2004_MAP_ROTATION      a rotation that can mix game types
#   - UT2004_BALANCE_TEAMS     skill-based team balancing when a team game starts
#   - UT2004_MAX_OVERTIME      a limit on overtime in CTF and Bombing Run
#   - MATCH_STATS_*            LANCommander match statistics, through ut2004-stats-bridge
#
# When any of them is on, this copies LCServer.u into System/, adds LCServer.LCServerActor to
# [Engine.GameEngine] ServerActors in <UT2004_INI>, and writes the settings into its
# [LCServer.LCServerActor] section (replaced on every start). With all of them off, the
# ServerActors line is taken out again. The match statistics also start the bridge here, so it
# is listening before the server.

$iniPath = Join-Path $Env:SERVER_ROOT "System/$($Env:UT2004_INI)"
$package = '/usr/local/share/ut2004/LCServer/LCServer.u'
$actor   = 'LCServer.LCServerActor'
$section = '[LCServer.LCServerActor]'

function ConvertTo-Bool([string] $Value, [bool] $Default) {
    switch ("$Value".Trim().ToLowerInvariant()) {
        { $_ -in 'true', '1', 'yes', 'on' }   { return $true }
        { $_ -in 'false', '0', 'no', 'off' } { return $false }
        default                              { return $Default }
    }
}

function Get-Int([string] $Value, [int] $Default) {
    $result = 0
    if ([int]::TryParse("$Value".Trim(), [ref] $result)) { return $result }
    return $Default
}

if (-not (Test-Path -LiteralPath $iniPath)) {
    Write-Log -Level Warning "LCServer: $iniPath doesn't exist; skipping the rotation, team balancing and match statistics"
    return
}

# auto (or anything else): on when there is somewhere to send them
$stats = ConvertTo-Bool $Env:MATCH_STATS_ENABLED ([bool]($Env:MATCH_STATS_SERVER_URL -and $Env:MATCH_STATS_TOKEN))

$rotation    = @("$Env:UT2004_MAP_ROTATION" -split '[;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$balance     = ConvertTo-Bool $Env:UT2004_BALANCE_TEAMS $false
$minBalance  = Get-Int $Env:UT2004_BALANCE_MIN_PLAYERS 4
$overtime    = Get-Int $Env:UT2004_MAX_OVERTIME 0
$statsPort   = Get-Int $Env:UT2004_STATS_BRIDGE_PORT 7790

$wanted = $stats -or $rotation.Count -gt 0 -or $balance -or $overtime -gt 0

$text    = [System.IO.File]::ReadAllText($iniPath)
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines   = [System.Collections.Generic.List[string]]::new([string[]]($text -split '\r?\n'))

# ---- ServerActors=LCServer.LCServerActor in [Engine.GameEngine] ----
$engineStart = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -ieq '[Engine.GameEngine]') { $engineStart = $i; break }
}

if ($engineStart -lt 0) {
    Write-Log -Level Warning "LCServer: $iniPath has no [Engine.GameEngine] section; skipping"
    return
}

$engineEnd = $lines.Count
for ($i = $engineStart + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*\[') { $engineEnd = $i; break }
}

$existing = -1
$lastActor = $engineStart
for ($i = $engineStart + 1; $i -lt $engineEnd; $i++) {
    if ($lines[$i] -match '^\s*ServerActors\s*=\s*(.+?)\s*$') {
        $lastActor = $i
        if ($Matches[1] -ieq $actor) { $existing = $i }
    }
}

if ($wanted -and $existing -lt 0) {
    $lines.Insert($lastActor + 1, "ServerActors=$actor")
} elseif (-not $wanted -and $existing -ge 0) {
    $lines.RemoveAt($existing)
}

# ---- [LCServer.LCServerActor] ----
$start = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -ieq $section) { $start = $i; break }
}
if ($start -ge 0) {
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[') { $end = $i; break }
    }
    $lines.RemoveRange($start, $end - $start)
    # The blank line that separated it
    if ($start -lt $lines.Count -and $start -gt 0 -and $lines[$start - 1].Trim() -eq '' -and $lines[$start].Trim() -eq '') {
        $lines.RemoveAt($start)
    }
}

if ($wanted) {
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -eq '') { $lines.RemoveAt($lines.Count - 1) }

    $lines.Add('')
    $lines.Add($section)
    $lines.Add("bMatchStats=$(if ($stats) { 'True' } else { 'False' })")
    $lines.Add('StatsHost=127.0.0.1')
    $lines.Add("StatsPort=$statsPort")
    $lines.Add("bRotation=$(if ($rotation.Count -gt 0) { 'True' } else { 'False' })")
    foreach ($entry in $rotation) { $lines.Add("MapRotation=$entry") }
    $lines.Add("bBalanceTeams=$(if ($balance) { 'True' } else { 'False' })")
    $lines.Add("BalanceMinPlayers=$minBalance")
    $lines.Add("MaxOvertimeMinutes=$overtime")
    $lines.Add('')
}

[System.IO.File]::WriteAllText($iniPath, ($lines -join $newline))
chown "$($Env:UID):$($Env:GID)" $iniPath

if (-not $wanted) {
    Write-Log "LCServer is off (no UT2004_MAP_ROTATION, UT2004_BALANCE_TEAMS, UT2004_MAX_OVERTIME or match statistics)"
    return
}

# ---- The package ----
$target = Join-Path $Env:SERVER_ROOT 'System/LCServer.u'
if (-not (Test-Path -LiteralPath $target) -or
    (Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $package).Hash) {
    Copy-Item -Force -LiteralPath $package -Destination $target
    chown "$($Env:UID):$($Env:GID)" $target
}

$features = @()
if ($rotation.Count -gt 0) { $features += "a $($rotation.Count)-map rotation" }
if ($balance)              { $features += "team balancing (from $minBalance players)" }
if ($overtime -gt 0)       { $features += "a $overtime-minute overtime limit" }
if ($stats)                { $features += "match statistics to $($Env:MATCH_STATS_SERVER_URL)" }
Write-Log "LCServer is on: $($features -join ', ')"

if (-not $stats) {
    return
}

# ---- ut2004-stats-bridge ----
# Undelivered matches and the Interposer's logs go to /config/.interposer/
$Env:INTERPOSER_BASE_DIRECTORY = $Env:CONFIG_DIR
$Env:UT2004_STATS_BRIDGE_PORT  = "$statsPort"

Get-Process -Name 'ut2004-stats-bridge' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Start-Process -NoNewWindow -FilePath 'gosu' -ArgumentList @("$($Env:UID):$($Env:GID)", '/usr/local/bin/ut2004-stats-bridge')

# Listening before the server starts (a LISTEN socket on the port in /proc/net/tcp)
$listen = ':{0:X4} 00000000:0000 0A' -f $statsPort
for ($i = 0; $i -lt 50; $i++) {
    if ((Get-Content -Raw -Path '/proc/net/tcp') -match [regex]::Escape($listen)) { break }
    Start-Sleep -Milliseconds 100
}
