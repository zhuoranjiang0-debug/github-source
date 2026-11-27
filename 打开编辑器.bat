@echo off
rem Open the editor -- the main entry point of this project.
rem
rem Inside the editor:
rem   drag an object from the bottom bar onto the canvas
rem   click to select, drag to move
rem   wheel = zoom, middle-drag = pan
rem   Ctrl+Z undo, Delete remove, F5 play, Ctrl+S save
rem
rem NOTE: keep this file ASCII-only. cmd.exe reads .bat with the OEM code
rem page (GBK on Chinese Windows), so UTF-8 Chinese would be garbled here.
cd /d "%~dp0"

rem ---- One-time setup ----------------------------------------------------
rem The engine is not shipped with this package: it is 164 MB and you only
rem need it once. Put Godot_v4.6.1-stable_win64.exe in this folder first.
if not exist "%~dp0Godot_v4.6.1-stable_win64.exe" (
    echo.
    echo   Godot engine not found.
    echo   Put Godot_v4.6.1-stable_win64.exe in this folder first.
    echo   Download link is in README.md - take version 4.6.1, Windows build.
    echo.
    pause
    exit /b 1
)

rem First run in a fresh copy: Godot must scan the project once to build the
rem .godot cache. Without it every script that references another by class_name
rem fails to parse -- the app reports hundreds of errors and nothing works.
rem This is a no-op after the first time.
if not exist "%~dp0app\.godot" (
    echo Preparing the project for first run, this takes a few seconds...
    "%~dp0Godot_v4.6.1-stable_win64.exe" --headless --path "%~dp0app" --import
)

start "" "%~dp0Godot_v4.6.1-stable_win64.exe" --path "%~dp0app"
