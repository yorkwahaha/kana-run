@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
rem ============================================================
rem  KANA RUN  --  double-click to play
rem  (This file is intentionally ASCII-only so it runs on any
rem   Windows code page. Chinese notes live in README.md.)
rem ============================================================
title Kana Run

set "GODOT="
if defined GODOT_BIN set "GODOT=%GODOT_BIN%"

if not defined GODOT if exist "I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe" set "GODOT=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT if exist "I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe" set "GODOT=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe"
if not defined GODOT if exist "%LOCALAPPDATA%\Programs\Godot\Godot.exe" set "GODOT=%LOCALAPPDATA%\Programs\Godot\Godot.exe"

if not defined GODOT if exist "I:\Projects\" for /f "delims=" %%G in ('dir /b /s "I:\Projects\Godot*\Godot_v*-stable_win64.exe" 2^>nul') do set "GODOT=%%G"

if not defined GODOT for %%G in (godot.exe godot4.exe godot) do if not defined GODOT for /f "delims=" %%P in ('where %%G 2^>nul') do set "GODOT=%%P"

if not defined GODOT goto :nogodot

echo.
echo   Godot: %GODOT%
echo.
echo   Importing assets (needed so dropped .mp3 files can be loaded)...
"%GODOT%" --headless --path "%CD%" --import >nul 2>&1
echo   Done.
echo.
echo   Starting game...  (close the window to quit)
echo.
"%GODOT%" --path "%CD%" --release
set "RC=%ERRORLEVEL%"
echo.
echo   Exited with code %RC%
timeout /t 3 >nul
exit /b %RC%

:nogodot
echo.
echo   [ERROR] Cannot find the Godot executable.
echo.
echo   Fix it in any of these ways:
echo     1) Copy Godot_v4.7.2-stable_win64.exe into I:\Projects\Godot_v4.7.2\
echo     2) Set the GODOT_BIN environment variable to the full path, e.g.
echo          set GODOT_BIN=C:\Godot\Godot.exe
echo     3) Run it manually:
echo          "C:\Godot\Godot.exe" --path "%CD%" --release
echo.
echo   (Chinese version of this note: README.md)
echo.
pause
exit /b 1
