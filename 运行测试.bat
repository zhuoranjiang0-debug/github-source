@echo off
rem Double-click to run the full automated test suite.
rem The Godot Windows binary is a GUI subsystem app and does not attach stdout
rem to the console, so its output is unreadable when run directly. We route it
rem through --log-file and print that file instead.
rem NOTE: keep this file ASCII-only (see the other .bat files for why).
chcp 65001 >nul
cd /d "%~dp0"

set "A2D_TEST_LOG=%TEMP%\ai2d_test.log"
if exist "%A2D_TEST_LOG%" del /q "%A2D_TEST_LOG%"

rem ---- One-time setup ----------------------------------------------------
rem The engine is not shipped with this package -- see README.md.
if not exist "Godot_v4.6.1-stable_win64.exe" (
    echo.
    echo   Godot engine not found.
    echo   Put Godot_v4.6.1-stable_win64.exe in this folder first.
    echo   Download link is in README.md - take version 4.6.1, Windows build.
    echo.
    pause
    exit /b 1
)

rem First run in a fresh copy: build the .godot cache before running tests.
rem Without it, every script that references another by class_name fails to
rem parse and the test run reports hundreds of bogus errors.
if not exist "app\.godot" (
    echo Preparing the project for first run, this takes a few seconds...
    Godot_v4.6.1-stable_win64.exe --headless --path app --import >nul 2>&1
)

Godot_v4.6.1-stable_win64.exe --headless --path app --script res://tests/run_tests.gd --log-file "%A2D_TEST_LOG%" >nul 2>&1
set "A2D_TEST_CODE=%ERRORLEVEL%"

if exist "%A2D_TEST_LOG%" (
    type "%A2D_TEST_LOG%"
) else (
    echo No log file was produced -- the tests probably did not start at all.
)

echo.
if "%A2D_TEST_CODE%"=="0" (
    echo RESULT: all tests passed.
) else (
    echo RESULT: some tests FAILED. Please send me the output above.
)
echo.
pause
