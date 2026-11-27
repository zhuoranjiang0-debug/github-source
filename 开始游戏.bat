@echo off
rem Double-click to play the sample prototype (Jumping Dino).
rem NOTE: keep this file ASCII-only. cmd.exe reads .bat using the OEM code page
rem (GBK on Chinese Windows), so UTF-8 Chinese here would be garbled and can
rem even break the script. Chinese explanations live in the chat / README.
cd /d "%~dp0"

rem ---- One-time setup ----------------------------------------------------
rem The engine is not shipped with this package -- see README.md.
if not exist "%~dp0Godot_v4.6.1-stable_win64.exe" (
    echo.
    echo   Godot engine not found.
    echo   Put Godot_v4.6.1-stable_win64.exe in this folder first.
    echo   Download link is in README.md - take version 4.6.1, Windows build.
    echo.
    pause
    exit /b 1
)

rem First run in a fresh copy needs one import pass -- see the editor .bat file.
if not exist "%~dp0app\.godot" (
    echo Preparing the project for first run, this takes a few seconds...
    "%~dp0Godot_v4.6.1-stable_win64.exe" --headless --path "%~dp0app" --import
)

start "" "%~dp0Godot_v4.6.1-stable_win64.exe" --path "%~dp0app" -- --play
