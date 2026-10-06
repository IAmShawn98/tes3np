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

copy /y "%PACKAGE%\tes3np.exe" "%~dp0tes3np.exe" >nul
if errorlevel 1 goto :failed

echo.
echo ========================================
echo             BUILD COMPLETE
echo ========================================
echo.
echo tes3np.exe is ready in this folder.
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
