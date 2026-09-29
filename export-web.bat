@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Kana Run - Export Web
rem ASCII-only on purpose. See README.md for the Chinese description.

set "GODOTC="
if defined GODOT_BIN set "GODOTC=%GODOT_BIN%"
if not defined GODOTC if exist "I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe" set "GODOTC=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe"
if not defined GODOTC if exist "I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe" set "GODOTC=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe"
if not defined GODOTC if exist "I:\Projects\" for /f "delims=" %%G in ('dir /b /s "I:\Projects\Godot*\Godot_v*-stable_win64_console.exe" 2^>nul') do set "GODOTC=%%G"
if not defined GODOTC goto :nogodot

rem Godot will NOT create the output folder for a web export. It fails with
rem "target folder does not exist" -- and, confusingly, sometimes also with an
rem empty "Cannot export project with preset Web due to configuration errors:".
rem That empty error looks like a missing export template or a broken preset,
rem but the real cause is usually just the missing folder. Hence this mkdir.
if not exist "build\web" mkdir "build\web"

echo.
echo   Exporting web build to build\web ... (takes a minute)
echo.
"%GODOTC%" --headless --path "%CD%" --export-release "Web" "build\web\index.html"

rem Inject the audio-unlock script into index.html.
rem
rem This CANNOT be done from inside the Godot project: the AudioContext lives in
rem index.js module scope, so neither GDScript's JavaScriptBridge nor a web
rem export preset option can reach it. It has to be a <script> that runs BEFORE
rem index.js -- which means it has to be injected into the generated HTML.
rem
rem Godot regenerates index.html on every export, so this must run after each one.
if exist "web\audio_unlock.html" (
    echo   Injecting web\audio_unlock.html ...
    powershell -NoProfile -ExecutionPolicy Bypass -File "tools\inject_web_audio.ps1"
    if errorlevel 1 (
        echo   [WARN] audio unlock injection failed -- web build will be silent
    )
) else (
    echo   [WARN] web\audio_unlock.html not found -- web build will be silent
)
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo   OK  ->  build\web\index.html
    echo   Deploy the whole build\web folder to any static host
    echo   (Cloudflare Pages / Vercel / itch.io / GitHub Pages).
    echo.
    choice /C YN /N /T 10 /M "Open in browser now? "
    if errorlevel 2 exit /b 0
    start "" "build\web\index.html"
) else (
    echo   [ERROR] export failed, exit code %RC%
    echo.
    echo   Two causes, in order of likelihood:
    echo     1. build\web could not be created -- delete it and re-run
    echo     2. Export templates missing. In the editor run
    echo        Project ^> Tools ^> Manage Export Templates...
    echo        and install the templates for 4.7.2-stable.
    echo.
    echo   Godot 4.7 prints an EMPTY "configuration errors:" line here,
    echo   so do not trust that message -- check the two items above first.
)
echo.
pause
exit /b %RC%

:nogodot
echo   [ERROR] Cannot find Godot. Set the GODOT_BIN environment variable.
pause
exit /b 1
