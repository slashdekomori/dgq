@echo off
setlocal EnableExtensions
title Discord game faker

REM Windows PowerShell 5.1 ships with every Windows 10/11 and can compile the
REM idle helper; pwsh 7 is only a fallback (it uses waitfor.exe instead).
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=pwsh"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0play.ps1" %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
  echo.
  pause
)
exit /b %RC%
