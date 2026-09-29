@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Kana Run - Editor
rem ASCII-only on purpose. See README.md for the Chinese description.

set "GODOT="
if defined GODOT_BIN set "GODOT=%GODOT_BIN%"
if not defined GODOT if exist "I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe" set "GODOT=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT if exist "I:\Projects\" for /f "delims=" %%G in ('dir /b /s "I:\Projects\Godot*\Godot_v*-stable_win64.exe" 2^>nul') do set "GODOT=%%G"
if not defined GODOT for %%G in (godot.exe godot4.exe) do if not defined GODOT for /f "delims=" %%P in ('where %%G 2^>nul') do set "GODOT=%%P"
if not defined GODOT goto :nogodot

echo   Opening editor... (F5 to run, F6 to run current scene)
"%GODOT%" -e --path "%CD%"
exit /b %ERRORLEVEL%

:nogodot
echo   [ERROR] Cannot find Godot. Set the GODOT_BIN environment variable.
pause
exit /b 1
