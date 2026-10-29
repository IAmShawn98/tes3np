@echo off
setlocal
cd /d "%~dp0"

echo ========================================
echo          Building tes3np...
echo ========================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build-windows.ps1"
if errorlevel 1 goto :failed

set "PACKAGE=%~dp0dist\local-build"
if exist "%PACKAGE%" rmdir /s /q "%PACKAGE%"
mkdir "%PACKAGE%" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%~dp0dist\tes3np-windows.zip' -DestinationPath '%PACKAGE%' -Force"
if errorlevel 1 goto :failed

if not exist "%PACKAGE%\tes3np.exe" (
    echo Expected built executable was not found at:
    echo %PACKAGE%\tes3np.exe
    goto :failed
)

rem The root executable is used by local shortcuts and source-tree testing.
rem Never publish it without the complete client it needs beside itself.
if not exist "%PACKAGE%\client\tes3mp.exe" (
    echo Bundled markerless TES3MP client is missing from the release.
    goto :failed
)
if not exist "%PACKAGE%\client\defaults.bin" (
    echo Bundled TES3MP runtime is incomplete: defaults.bin is missing.
    goto :failed
)
if not exist "%PACKAGE%\client\tes3mp-client-default.cfg" (
    echo Bundled TES3MP runtime is incomplete: tes3mp-client-default.cfg is missing.
    goto :failed
)

rem Copy runtime first so a previous root launcher is never replaced without it.
if not exist "%~dp0client" mkdir "%~dp0client"
xcopy /e /i /h /y "%PACKAGE%\client\*" "%~dp0client\" >nul
if errorlevel 1 goto :failed
if not exist "%~dp0client\tes3mp.exe" goto :failed
if not exist "%~dp0client\defaults.bin" goto :failed
if not exist "%~dp0client\tes3mp-client-default.cfg" goto :failed

if not exist "%~dp0licenses" mkdir "%~dp0licenses"
if exist "%PACKAGE%\licenses\TES3MP\LICENSE" (
    xcopy /e /i /h /y "%PACKAGE%\licenses\*" "%~dp0licenses\" >nul
    if errorlevel 1 goto :failed
)

if not exist "%PACKAGE%\chat-host\tes3np.ChatHost.exe" (
    echo WebView2 chat host was not packaged.
    goto :failed
)
if not exist "%~dp0chat-host" mkdir "%~dp0chat-host"
xcopy /e /i /y "%PACKAGE%\chat-host\*" "%~dp0chat-host\" >nul
if errorlevel 1 goto :failed

rem Publish the launcher last after all bundled dependencies are present.
copy /y "%PACKAGE%\tes3np.exe" "%~dp0tes3np.exe" >nul
if errorlevel 1 goto :failed

echo.
echo ========================================
echo             BUILD COMPLETE
echo ========================================
echo.
echo tes3np.exe and its bundled TES3MP client are ready in this folder.
echo.
pause
exit /b 0

:failed
echo.
echo ========================================
echo              BUILD FAILED
echo ========================================
echo.
echo The build did not finish successfully.
echo Read the error above, then press any key.
echo.
pause
exit /b 1
