# dgq

Discord Quests make you play a game for a while (usually 15 minutes) before you can claim the reward. You can get that reward without installing the game.

dgq looks up the game in Discord's list of detectable games. Then it starts a small do-nothing process under the exe name and folder layout Discord expects (for example `bin/x64/witcher3.exe`). Discord sees that process and shows you as "Playing <game>". The quest progress counts up while it runs. Stop it and the process and its files are gone.

Nothing is installed and no game files are downloaded. The games list is fetched fresh from Discord on every run, so new quest games work right away.

## Help

**Linux** (needs `curl` and `jq`; a C compiler is optional but recommended):

```sh
./dgq                  # ask for a game name, then play it
./dgq witcher 3        # search, pick if several match, play until Enter / Ctrl-C
./dgq -n witcher 3     # dry run: show the exe it would fake, start nothing
./dgq -l witcher       # list matching games and their executables
./dgq -h               # help
```

**Windows**: unzip `dgq-win.zip` (build it with `./build-win.sh`), double-click `Play.bat`, and type the game name. `Play.bat /check <name>` and `Play.bat /list <name>` work the same way as `-n` and `-l`. More details are in `win/README.txt`.

**If it doesn't show up**: make sure Discord's Activity Privacy setting shares your detected activity, and give it about 15 seconds.
