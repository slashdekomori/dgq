DISCORD GAME FAKER
==================

Makes Discord show you as "Playing <game>" without owning or launching it.

HOW TO USE
----------
1. Start Discord.
2. Double-click Play.bat
3. Type part of a game name (e.g. witcher 3, garrys mod, cs2) and press Enter.
4. If several games match, type the number and press Enter.
5. Discord picks it up within about 15 seconds.
6. Press Enter in the window to stop. Closing the window also works.

Nothing is installed. A small do-nothing program is copied into
%TEMP%\dgq-run\ under the game's exe name and folder layout (for example
bin\x64\witcher3.exe), and deleted when you stop. The first run compiles that
program with the C# compiler built into Windows and keeps it in
%LOCALAPPDATA%\dgq\.

The list of games is downloaded from Discord each time you start it (while
you type), so new games work right away. You need to be online.

OTHER COMMANDS
--------------
Play.bat /check witcher 3   show the game, app id and exe it would use,
                            without launching anything
Play.bat /list witcher      list matching games and their exe files

IF IT DOESN'T SHOW UP
---------------------
* Discord > User Settings > Activity Privacy: sharing your detected
  activity must be turned ON.
* Discord > User Settings > Registered Games (or "Game Activity"): the game
  should be listed while the window is open. If it is toggled off there,
  turn it on.
* Antivirus may block a freshly made exe in %TEMP%. Allow the
  %TEMP%\dgq-run folder, or the file %LOCALAPPDATA%\dgq\idle-1.exe.
* Some games show the name and icon but no extra details. Those use
  Discord's game hooks, which a fake process can't provide.

FILES
-----
Play.bat    double-click launcher
play.ps1    the logic
