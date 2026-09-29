@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Kana Run - Self Test
rem ASCII-only on purpose. See README.md for the Chinese description.

set "GODOTC="
if defined GODOT_BIN set "GODOTC=%GODOT_BIN%"
if not defined GODOTC if exist "I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe" set "GODOTC=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe"
if not defined GODOTC if exist "I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe" set "GODOTC=I:\Projects\Godot_v4.7.2\Godot_v4.7.2-stable_win64.exe"
if not defined GODOTC if exist "I:\Projects\" for /f "delims=" %%G in ('dir /b /s "I:\Projects\Godot*\Godot_v*-stable_win64_console.exe" 2^>nul') do set "GODOTC=%%G"
if not defined GODOTC goto :nogodot

echo.
echo ==========================================================
echo  1/6  question generator self-test
echo ==========================================================
"%GODOTC%" --headless --path "%CD%" -- --selftest
echo.
echo ==========================================================
echo  2/6  input pipeline (keyboard + touch gestures)
echo ==========================================================
"%GODOTC%" --headless --path "%CD%" --script "%CD%\tools\input_test.gd" 2>&1 | findstr /C:"FAIL" /C:"[input-test]"
echo.
echo ==========================================================
echo  3/6  runner ground contact (kneel / prone)
echo ==========================================================
"%GODOTC%" --headless --path "%CD%" --script "%CD%\tools\prone_test.gd" 2>&1 | findstr /C:"FAIL" /C:"[prone-test]"
echo.
echo ==========================================================
echo  4/6  word-question audio coverage
echo ==========================================================
"%GODOTC%" --headless --path "%CD%" --script "%CD%\tools\word_audio_test.gd" 2>&1 | findstr /C:"FAIL" /C:"[word-audio]"
echo.
echo ==========================================================
echo  5/6  full run, no mistakes  (watch = stone check)
echo ==========================================================
"%GODOTC%" --headless --path "%CD%" --quit-after 20000 -- --watch --perfect --turbo=20 2>&1 | findstr /C:"[watch]" /C:"[kana-run]"
echo.
echo ==========================================================
echo  6/6  full run, with mistakes
echo ==========================================================
"%GODOTC%" --headless --path "%CD%" --quit-after 20000 -- --watch --autoplay --turbo=20 2>&1 | findstr /C:"[watch]" /C:"[kana-run]"
echo.
echo   "missing 0 frames total" means all three stelae were on screen
echo   for the entire run, i.e. no bug.
echo   "fail 0" in stages 2-4 means input, ground contact and
echo   word-question audio are all correct.
echo.
pause
exit /b 0

:nogodot
echo   [ERROR] Cannot find Godot. Set the GODOT_BIN environment variable.
pause
exit /b 1
