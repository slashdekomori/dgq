# play.ps1 - make Discord show "Playing <game>" by running an idle process at
# the executable path Discord's detectable-games list expects for that game.
#
#   Play.bat                     ask for a game name, then play it
#   Play.bat witcher 3           search, pick if ambiguous, play until Enter
#   Play.bat /check witcher 3    dry run: show what would be started
#   Play.bat /list witcher       list matching games and their executables
#
# The games list is downloaded fresh on every start (while you type the name),
# so it is always current and nothing is stored.
# Nothing is installed. The fake exe lives in %TEMP%\dgq-run\<pid>\ and is
# removed when you stop; it also quits by itself if this window is closed.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less files as ANSI.

param(
    [switch]$Check,
    [switch]$List,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest
)

$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = 'Discord game faker' } catch { }
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$words = @()
foreach ($t in $Rest) {
    switch ($t) {
        '/check'  { $Check = $true; continue }
        '/list'   { $List = $true; continue }
        default   { if (-not [string]::IsNullOrWhiteSpace($t)) { $words += $t } }
    }
}
$query = ($words -join ' ').Trim()

$runRoot = Join-Path ([IO.Path]::GetTempPath()) 'dgq-run'
$cacheDir = Join-Path $env:LOCALAPPDATA 'dgq'

function Say([string]$text, [string]$color = 'Gray') { Write-Host $text -ForegroundColor $color }

# --- games list --------------------------------------------------------------
# Downloaded and parsed in a background runspace so it is ready by the time
# the name is typed. Launchers (never matched by Discord) and non-Windows
# entries are dropped. Rows: Name, Id, Aliases, Exes (Os, Path, Args), plus
# search keys precomputed here so searching later is fast: Keys (normalized
# name and aliases, same as Norm) and Bases (exe file names without extension).
$loader = {
    param($url)
    $quote = New-Object Regex '[''\u2019]'
    $punct = New-Object Regex '[^\p{L}\p{N}]+'
    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $req = [Net.HttpWebRequest]::Create($url)
    $req.UserAgent = 'dgq'
    $req.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate   # 2 MB instead of 13
    $resp = $req.GetResponse()
    try { $json = (New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)).ReadToEnd() }
    finally { $resp.Close() }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $apps = @($json | ConvertFrom-Json)
    } else {
        # 5.1's ConvertFrom-Json chokes on a document this size
        Add-Type -AssemblyName System.Web.Extensions
        $ser = New-Object Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        $apps = @($ser.DeserializeObject($json))
    }
    if ($apps.Count -eq 0) { throw 'unexpected response from Discord' }
    foreach ($a in $apps) {
        $exes = [Collections.Generic.List[object]]::new()
        $bases = [Collections.Generic.List[string]]::new()
        foreach ($x in @($a.executables)) {
            if ($null -eq $x -or $x.is_launcher -or $x.os -ne 'win32' -or [string]::IsNullOrEmpty($x.name)) { continue }
            $path = [string]$x.name
            $exes.Add([pscustomobject]@{ Os = 'win32'; Path = $path; Args = [string]$x.arguments })
            $file = $path.Substring($path.LastIndexOf('/') + 1).TrimStart('>').ToLowerInvariant()
            $dot = $file.LastIndexOf('.')
            $bases.Add($(if ($dot -gt 0) { $file.Substring(0, $dot) } else { $file }))
        }
        if ($exes.Count -eq 0) { continue }
        $aliases = [Collections.Generic.List[string]]::new()
        $keys = [Collections.Generic.List[string]]::new()
        foreach ($n in @($a.aliases)) { if ($n) { $aliases.Add([string]$n) } }
        foreach ($n in @([string]$a.name) + $aliases) {
            $k = $punct.Replace($quote.Replace($n.ToLowerInvariant(), ''), ' ').Trim()
            if ($k) { $keys.Add($k) }
        }
        [pscustomobject]@{
            Name = [string]$a.name; Id = [string]$a.id; Aliases = $aliases.ToArray()
            Exes = $exes.ToArray(); Keys = $keys.ToArray(); Bases = $bases.ToArray()
        }
    }
}
$fetch = [powershell]::Create().AddScript($loader).AddArgument('https://discord.com/api/v10/applications/detectable')
$fetchJob = $fetch.BeginInvoke()

function Get-Games {
    if (-not $fetchJob.IsCompleted) { Say '  loading the games list...' DarkGray }
    try { $rows = @($fetch.EndInvoke($fetchJob)) }
    catch { throw "could not get the games list from Discord: $($_.Exception.InnerException.Message)" }
    if ($rows.Count -eq 0) { throw 'Discord returned an empty games list' }
    return $rows
}

# --- search ------------------------------------------------------------------
# Same ranking as dgq: exact name/alias, leading words, whole-word phrase
# (or exe file name), substring, then all words present. Lowercase, apostrophes
# dropped, other punctuation folded to spaces ($loader builds Keys the same way).
function Norm([string]$s) {
    if (-not $s) { return '' }
    $s = $s.ToLowerInvariant() -replace '[''\u2019]', ''
    return ($s -replace '[^\p{L}\p{N}]+', ' ').Trim()
}

function Find-Games($rows, [string]$needle) {
    if ($needle -match '^\d{15,}$') {
        return @(foreach ($g in $rows) { if ($g.Id -eq $needle) { [pscustomobject]@{ Rank = 0; Len = 0; Game = $g } } })
    }
    $q = Norm $needle
    if (-not $q) { return @() }
    $tokens = $q.Split(' ')
    $lead = "$q "; $word = " $q "
    $hits = foreach ($g in $rows) {
        $best = 99
        foreach ($n in $g.Keys) {
            if ($n -eq $q) { $r = 0 }
            elseif ("$n ".StartsWith($lead, [StringComparison]::Ordinal)) { $r = 1 }
            elseif (" $n ".Contains($word)) { $r = 2 }
            elseif ($n.Contains($q)) { $r = 3 }
            else { $r = 4; foreach ($t in $tokens) { if (-not $n.Contains($t)) { $r = 99; break } } }
            if ($r -lt $best) { $best = $r }
        }
        if ($best -gt 2 -and $g.Bases -contains $q) { $best = 2 }
        if ($best -lt 99) { [pscustomobject]@{ Rank = $best; Len = $g.Name.Length; Game = $g } }
    }
    return @($hits | Sort-Object Rank, Len, @{ Expression = { $_.Game.Name } })
}

function Show-Game($g) {
    Write-Host ('{0}  ' -f $g.Name) -NoNewline -ForegroundColor White
    Say $g.Id DarkGray
    foreach ($e in $g.Exes) { Say ('    {0,-6} {1}  {2}' -f $e.Os, $e.Path, $e.Args) }
}

# Returns the chosen game, or $null. Asks when the query is ambiguous.
function Select-Game($rows, [string]$needle) {
    $hits = @(Find-Games $rows $needle)
    if ($hits.Count -eq 0) {
        Say "  No game matching '$needle'. Try a shorter part of the name." Yellow
        return $null
    }
    if ($hits.Count -eq 1 -or ($hits[0].Rank -eq 0 -and $hits[1].Rank -ne 0)) { return $hits[0].Game }
    $max = [Math]::Min($hits.Count, 20)
    Write-Host ''
    for ($i = 0; $i -lt $max; $i++) { Write-Host ('  {0,2}) {1}' -f ($i + 1), $hits[$i].Game.Name) }
    if ($hits.Count -gt $max) { Say ("  ... and {0} more - refine the search" -f ($hits.Count - $max)) DarkGray }
    Write-Host ''
    $pick = Read-Host ("Pick 1-{0} (Enter to cancel)" -f $max)
    if ([string]::IsNullOrWhiteSpace($pick)) { return $null }
    $n = 0
    if (-not [int]::TryParse($pick.Trim(), [ref]$n) -or $n -lt 1 -or $n -gt $max) {
        Say '  Not a valid choice.' Yellow
        return $null
    }
    return $hits[$n - 1].Game
}

# --- exe ---------------------------------------------------------------------
# Discord matches the end of the process path against the listed exe path
# (e.g. bin\x64\witcher3.exe), so the folders matter, not just the file name.
# A leading '>' means "file name must match exactly"; it is not part of the name.
function Get-ExePath($g) {
    $bad = [IO.Path]::GetInvalidFileNameChars()
    foreach ($e in $g.Exes) {
        if ($e.Os -ne 'win32') { continue }
        $parts = $e.Path.TrimStart('>').Split('/')
        $ok = $true
        foreach ($p in $parts) {
            if (-not $p -or $p -eq '.' -or $p -eq '..' -or $p.IndexOfAny($bad) -ge 0 -or $p.EndsWith('.') -or $p.EndsWith(' ')) { $ok = $false; break }
        }
        if ($ok) { return [pscustomobject]@{ Rel = ($parts -join '\'); Args = $e.Args } }
    }
    return $null
}

# The helper idles until killed and exits when the PowerShell process that
# started it goes away (window closed), so Discord never keeps a stale game.
# It is compiled once with the C# compiler built into Windows. If that is not
# possible, a copy of waitfor.exe is used (no game arguments, no auto-exit).
$helperSource = @'
using System;
using System.Diagnostics;
using System.Threading;
static class Idle {
    static void Main() {
        int ppid;
        if (int.TryParse(Environment.GetEnvironmentVariable("DGQ_PARENT"), out ppid)) {
            try { Process.GetProcessById(ppid).WaitForExit(); } catch { }
            return;
        }
        Thread.Sleep(Timeout.Infinite);
    }
}
'@

function Get-Helper {
    $exe = Join-Path $cacheDir 'idle-1.exe'
    if (-not (Test-Path -LiteralPath $exe) -and $PSVersionTable.PSVersion.Major -lt 6) {
        try {
            New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
            Add-Type -TypeDefinition $helperSource -OutputAssembly $exe -OutputType WindowsApplication
        } catch {
            Remove-Item -LiteralPath $exe -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $exe) { return [pscustomobject]@{ Path = $exe; Kind = 'idle' } }
    $wait = Join-Path $env:SystemRoot 'System32\waitfor.exe'
    if (Test-Path -LiteralPath $wait) { return [pscustomobject]@{ Path = $wait; Kind = 'waitfor' } }
    throw 'no helper available: could not compile one and waitfor.exe is missing'
}

# Removes leftovers of runs whose PowerShell window is gone.
function Clear-Stale {
    if (-not (Test-Path -LiteralPath $runRoot)) { return }
    foreach ($d in Get-ChildItem -LiteralPath $runRoot -Directory) {
        $owner = 0
        if ([int]::TryParse($d.Name, [ref]$owner) -and (Get-Process -Id $owner -ErrorAction SilentlyContinue)) { continue }
        $prefix = $d.FullName + '\'
        Get-Process -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
        } | Stop-Process -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Start-Game($g) {
    $exe = Get-ExePath $g
    if (-not $exe) {
        Say "  '$($g.Name)' has no Windows executable dgq can use." Yellow
        return 1
    }
    $helper = Get-Helper
    $base = Join-Path $runRoot $PID
    $fake = Join-Path $base $exe.Rel
    $argLine = if ($helper.Kind -eq 'idle') { $exe.Args } else { "/t 99999 dgq$PID" }

    if ($Check) {
        Write-Host ''
        Write-Host ('  game   : {0}' -f $g.Name)
        Write-Host ('  app id : {0}' -f $g.Id)
        Write-Host ('  exe    : {0}' -f $exe.Rel)
        if ($exe.Args) { Write-Host ('  args   : {0}' -f $exe.Args) }
        Write-Host ('  run    : {0} {1}' -f $fake, $argLine)
        Write-Host ('  helper : {0} ({1})' -f $helper.Path, $helper.Kind)
        Say '  (check mode - nothing launched)' DarkGray
        return 0
    }
    if ($exe.Args -and $helper.Kind -ne 'idle') {
        Say "  Warning: Discord expects arguments '$($exe.Args)' for this game, which waitfor.exe cannot take." Yellow
    }

    Clear-Stale
    $proc = $null
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $fake) | Out-Null
        Copy-Item -LiteralPath $helper.Path -Destination $fake -Force
        $env:DGQ_PARENT = "$PID"
        $start = @{ FilePath = $fake; PassThru = $true; WindowStyle = 'Hidden' }
        if ($argLine) { $start.ArgumentList = $argLine }
        $proc = Start-Process @start
        Remove-Item Env:DGQ_PARENT -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 700
        if ($proc.HasExited) { throw "the helper process exited immediately (code $($proc.ExitCode))" }

        Write-Host ''
        Write-Host '  Now playing: ' -NoNewline -ForegroundColor Green
        Write-Host $g.Name -ForegroundColor White
        Say "  as $($exe.Rel). Discord picks it up within ~15 seconds." DarkGray
        Say '  Press Enter to stop (closing this window also works).' DarkGray
        Write-Host ''
        [void](Read-Host)
        return 0
    }
    catch {
        Say "  Failed: $($_.Exception.Message)" Red
        Say '  If antivirus blocked it, allow the dgq-run folder in %TEMP%.' DarkGray
        return 1
    }
    finally {
        if ($proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            try { $proc.WaitForExit(2000) | Out-Null } catch { }
        }
        Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- main --------------------------------------------------------------------
try {
    $rows = $null
    if ($List) {
        $rows = @(Get-Games)
        $games = @(if ($query) { Find-Games $rows $query | ForEach-Object { $_.Game } } else { $rows | Sort-Object Name })
        if ($games.Count -eq 0) { Say "No game matching '$query'." Yellow; exit 1 }
        foreach ($g in $games) { Show-Game $g }
        exit 0
    }

    $game = $null
    if ($query) {
        $rows = @(Get-Games)
        $game = Select-Game $rows $query
    } else {
        Write-Host ''
        Say '  Discord game faker' Cyan
        Say '  Type part of a game name, e.g. "witcher 3" or "cs2". Empty line quits.' DarkGray
        while (-not $game) {
            Write-Host ''
            $query = (Read-Host 'Game').Trim()
            if (-not $query) { exit 0 }
            if (-not $rows) { $rows = @(Get-Games) }
            $game = Select-Game $rows $query
        }
    }
    if (-not $game) { exit 1 }
    exit (Start-Game $game)
}
catch {
    Say "  Failed: $($_.Exception.Message)" Red
    exit 1
}
