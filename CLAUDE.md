# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A "game faker": the user types a game name, and the tool starts an idle process at the executable path that Discord's detectable-games list (`https://discord.com/api/v10/applications/detectable`) expects for that game, so Discord shows "Playing <game>". The process runs until the user stops it.

- **`dgq`** (Linux, bash): the CLI. It compiles a tiny C idle helper on first use (`~/.cache/dgq/idle-1`), falling back to a copy of `sleep` when there is no `cc`.
- **`win/`** (Windows): `Play.bat` → `play.ps1`. It compiles a C# idle helper with `Add-Type` on first use (`%LOCALAPPDATA%\dgq\idle-1.exe`), falling back to a copy of `waitfor.exe`.
- `dgq-win.zip` is the distributable built by `build-win.sh` from `win/`.

The games list is **never stored**: both tools download it at every launch, in the background while the user types the name (`fetch &` + `need_list` in `dgq`; a `[powershell]::Create()` runspace + `Get-Games` in `play.ps1`). Don't reintroduce a cached list or an update command.

This is not a git repo, and it has no test suite.

## Commands

```sh
./dgq witcher 3          # search, pick if ambiguous, run until Enter/Ctrl-C
./dgq -n witcher 3       # dry run: prints exe path, args, helper
./dgq -l garry           # list matches with their executables (-l alone: all)
./build-win.sh           # rebuild dgq-win.zip (do this after changing win/)
```

`dgq` needs curl and jq. Windows equivalents: `Play.bat [name]`, `/check`, `/list`. To test `play.ps1` without Windows, run it under pwsh 7 with `LOCALAPPDATA` and `SystemRoot` set. Search, `/list` and `/check` work there. The 5.1-only paths (the `Add-Type` exe compile and the `JavaScriptSerializer` JSON parse) and process launching can only be tested on Windows.

## How detection works (why the design is this way)

Discord matches a running process when the **end of its path** equals a listed exe `name`, which often includes folders (`bin/x64/witcher3.exe`; ~80% of entries). A leading `>` means the file name alone must match exactly. Some entries also need `arguments` to appear in the command line, and `is_launcher` entries are never matched. So both tools:

- recreate the full relative path under a per-run dir (`$XDG_RUNTIME_DIR/dgq-run/<pid>/…`, or `%TEMP%\dgq-run\<pid>\…`), with `>` stripped and unsafe segments (`..`, absolute paths, invalid Windows chars) rejected;
- pass the entry's `arguments` to the helper (the reason for a custom helper instead of `sleep`/`waitfor`);
- tie the helper's lifetime to the launcher (`DGQ_PARENT` env + `PR_SET_PDEATHSIG` on Linux, `WaitForExit` on the parent PID on Windows). Each run also sweeps run dirs whose owner PID is dead.

On Linux, `linux` entries are preferred over `win32` ones. Discord detects Windows exes too, as Wine/Proton processes. Windows only uses `win32` entries.

## Games list in memory

`dgq`'s `JQ_TSV` turns Discord's JSON into one TSV line per game, written to `$XDG_RUNTIME_DIR/dgq-run/<pid>/games.tsv` and deleted on exit: `name \t id \t aliases \t (os \t exe \t args)…`. The last three fields repeat per executable, and aliases are joined with `\x1f`. Only `win32` and `linux` entries are kept, launchers are dropped, and games with no exe left are dropped. Field splitting must keep empty `args` fields: use `mapfile -d $'\t'` (not `read -a`, which collapses tabs), and `-F'\t'` in awk.

`play.ps1`'s `$loader` builds row objects directly (win32 entries only), and precomputes `Keys` (normalized name + aliases) and `Bases` (exe names without extension) so `Find-Games` stays fast. In the loader, avoid per-item cmdlets (`New-Object`, `Where-Object`, `ForEach-Object`); they made loading several times slower. The full JSON parse is still the dominant cost (~2–4 s).

## Search

The ranking is implemented twice, in `AWK_SEARCH` in `dgq` and in `Norm`/`$loader` keys/`Find-Games` in `play.ps1`, and the two should behave identically. Names are compared lowercase, with apostrophes dropped and other punctuation folded to spaces. The ranks are:

0. exact name/alias
1. leading words
2. whole-word phrase or exe base name (`cs2` → `win64/cs2.exe`)
3. substring
4. all words present

Ties go to the shorter name. A unique rank-0 hit is picked without asking, and a 15+ digit query is treated as an app id.

## Constraints

- `play.ps1` must be ASCII-only (5.1 reads BOM-less files as ANSI; use regex escapes like `’`) and 5.1-compatible. `Play.bat` intentionally prefers 5.1 over pwsh because `Add-Type -OutputType WindowsApplication` doesn't work in PowerShell 6+.
- PowerShell functions unwrap one-element arrays on return; wrap calls in `@()`.
- `Play.bat` and `win/README.txt` use CRLF line endings. `README.txt` is end-user documentation shipped in the zip.
- `dgq -h` prints lines 2–13 of the script itself, so keep the header comment in sync.
