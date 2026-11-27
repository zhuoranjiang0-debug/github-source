@echo off
rem Rebuild the web version into build\web
rem
rem Needs the Godot export templates installed once
rem (Editor - Manage Export Templates, or the .tpz extracted into
rem  %APPDATA%\Godot\export_templates\4.6.1.stable\).
rem
rem NOTE: keep this file ASCII-only. cmd.exe reads .bat with the OEM code
rem page (GBK on Chinese Windows), so UTF-8 Chinese would be garbled.
cd /d "%~dp0"

if not exist "%~dp0Godot_v4.6.1-stable_win64.exe" (
    echo.
    echo   Godot engine not found.
    echo   Put Godot_v4.6.1-stable_win64.exe in this folder first.
    echo.
    pause
    exit /b 1
)

echo Building web version, this takes about ten seconds...
"%~dp0Godot_v4.6.1-stable_win64.exe" --headless --path "%~dp0app" --export-release "Web" "%~dp0build\web\index.html"

echo.
if exist "%~dp0build\web\index.html" (
    echo   Done. Output is in build\web\
    echo   Double-click the "serve" script in this folder to run it.
) else (
    echo   Build failed. See the messages above.
)
echo.
pause
