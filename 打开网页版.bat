@echo off
rem Serve the web build on this machine and open it in the browser.
rem
rem Why a server is needed: browsers refuse to load WebAssembly from a file://
rem path, so the build has to be served over http even locally.
rem
rem To open it on an iPad or phone: connect the device to the SAME Wi-Fi as this
rem computer, then type the IPv4 address printed below plus :8099 in its browser.
rem If the page does not load, allow python through the Windows firewall.
rem
rem NOTE: keep this file ASCII-only. cmd.exe reads .bat with the OEM code
rem page (GBK on Chinese Windows), so UTF-8 Chinese would be garbled.
cd /d "%~dp0"

if not exist "%~dp0build\web\index.html" (
    echo.
    echo   Web build not found. Run the "build web" script first.
    echo.
    pause
    exit /b 1
)

where python >nul 2>nul
if errorlevel 1 (
    echo.
    echo   Python not found in PATH. It is needed to serve the files.
    echo.
    pause
    exit /b 1
)

echo.
echo   Local:  http://localhost:8099/
echo.
echo   Other devices on the same Wi-Fi (iPad, phone) - open one of these:
ipconfig | findstr /C:"IPv4"
echo.
echo   Keep this window open while testing. Press Ctrl+C to stop.
echo.

start "" http://localhost:8099/index.html
python -m http.server 8099 --directory "%~dp0build\web"
