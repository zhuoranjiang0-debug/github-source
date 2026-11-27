@echo off
rem Build an Android APK into build\android\
rem
rem One-time setup is described in the Android build notes under docs\
rem (short version: an "android-tools" folder on the Desktop containing
rem  jdk\, sdk\ and debug.keystore).
rem
rem NOTE: keep this file ASCII-only. cmd.exe reads .bat with the OEM code
rem page (GBK on Chinese Windows), so UTF-8 Chinese would be garbled.
cd /d "%~dp0"

set "A2D_TOOLS=%USERPROFILE%\Desktop\android-tools"

if not exist "%~dp0Godot_v4.6.1-stable_win64.exe" (
    echo   Godot engine not found in this folder.
    pause
    exit /b 1
)
if not exist "%A2D_TOOLS%\jdk\bin\java.exe" (
    echo.
    echo   Android toolchain not found at:
    echo     %A2D_TOOLS%
    echo   See the Android build notes under docs\ for how to set it up once.
    echo.
    pause
    exit /b 1
)

set "JAVA_HOME=%A2D_TOOLS%\jdk"
set "PATH=%A2D_TOOLS%\jdk\bin;%PATH%"

if not exist "%~dp0build\android" mkdir "%~dp0build\android"

echo Building Android APK, this takes about ten seconds...
"%~dp0Godot_v4.6.1-stable_win64.exe" --headless --path "%~dp0app" --export-debug "Android" "%~dp0build\android\ai2d-debug.apk"

echo.
if exist "%~dp0build\android\ai2d-debug.apk" (
    echo   Done: build\android\ai2d-debug.apk
    echo   Copy it to an Android tablet and tap it to install.
) else (
    echo   Build failed. See the messages above.
)
echo.
pause
