@echo off
setlocal
cd /d "%~dp0"

echo ========================================
echo          Building tes3np...
echo ========================================
echo.

set "BUILD_STAGE=Compiling and validating distribution ZIP"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build-windows.ps1"
if errorlevel 1 goto :failed
echo BUILD CHECKPOINT ^| Verified distribution ZIP ready.

set "BUILD_STAGE=Clearing old local extraction"
set "PACKAGE=%~dp0dist\local-build"
if exist "%PACKAGE%" (
    rmdir /s /q "%PACKAGE%" >nul 2>&1
    if exist "%PACKAGE%" (
        echo Previous local-build folder is locked or in use.
        goto :failed
    )
)
set "BUILD_STAGE=Extracting validated distribution ZIP"
mkdir "%PACKAGE%" >nul 2>&1
if errorlevel 1 goto :failed

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

rem The extracted ZIP remains the trustworthy test candidate if any running
rem root launcher, Chat Host or antivirus lock blocks source-root installation.
set "BUILD_STAGE=Copying packaged TES3MP client into source folder"
rem Copy runtime first so a previous root launcher is never replaced without it.
if not exist "%~dp0client" mkdir "%~dp0client"
xcopy /e /i /h /y "%PACKAGE%\client\*" "%~dp0client\" >nul
if errorlevel 1 goto :failed
if not exist "%~dp0client\tes3mp.exe" goto :failed
if not exist "%~dp0client\defaults.bin" goto :failed
if not exist "%~dp0client\tes3mp-client-default.cfg" goto :failed

set "BUILD_STAGE=Copying packaged AutoHotkey runtime into source folder"
rem The compiled launcher starts AHK macros through the bundled official v2
rem interpreter. Publish it before replacing the root EXE, just like client.
if not exist "%PACKAGE%\runtime\AutoHotkey64.exe" (
    echo The bundled AutoHotkey v2 macro interpreter is missing.
    goto :failed
)
if not exist "%~dp0runtime" mkdir "%~dp0runtime"
xcopy /e /i /h /y "%PACKAGE%\runtime\*" "%~dp0runtime\" >nul
if errorlevel 1 goto :failed
if not exist "%~dp0runtime\AutoHotkey64.exe" goto :failed

set "BUILD_STAGE=Copying license notices into source folder"
if not exist "%~dp0licenses" mkdir "%~dp0licenses"
if exist "%PACKAGE%\licenses\TES3MP\LICENSE" (
    xcopy /e /i /h /y "%PACKAGE%\licenses\*" "%~dp0licenses\" >nul
    if errorlevel 1 goto :failed
)

set "BUILD_STAGE=Copying packaged Chat Host into source folder"
if not exist "%PACKAGE%\chat-host\tes3np.ChatHost.exe" (
    echo WebView2 chat host was not packaged.
    goto :failed
)
if not exist "%~dp0chat-host" mkdir "%~dp0chat-host"
xcopy /e /i /y "%PACKAGE%\chat-host\*" "%~dp0chat-host\" >nul
if errorlevel 1 goto :failed

set "BUILD_STAGE=Replacing source-root launcher executable"
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
echo Could not complete: %BUILD_STAGE%
echo.
echo If the ZIP integrity check above passed, the new test build remains at:
echo   %~dp0dist\tes3np-windows\tes3np.exe
echo Close running tes3np / Chat Host windows before reinstalling into
echo the source folder. Do not mistake the older root tes3np.exe for
echo the newly compiled candidate.
echo.
echo Read the error above, then press any key.
echo.
pause
exit /b 1
