@echo off
setlocal

set "CLICKER=C:\Develop\Clicker\Win32\Release\Clicker.exe"

if "%~1"=="" (
    echo Usage: "%~nx0" "script-name.script" [Debug=true^|false]
    exit /b 2
)

set "DEBUG_ARG=Debug=false"
if not "%~2"=="" (
    if /I "%~2"=="Debug=true" (
        set "DEBUG_ARG=Debug=true"
    ) else (
        echo Error: Invalid option "%~2". Use Debug=true or Debug=false.
        exit /b 2
    )
)

set "SCRIPT=C:\Scripts\%~1"

if not exist "%SCRIPT%" (
    echo Error: Script not found: "%SCRIPT%"
    exit /b 2
)

"%CLICKER%" --console "%SCRIPT%" %DEBUG_ARG%
if errorlevel 1 (
    echo Error: Script failed: "%SCRIPT%"
    exit /b 1
)

echo Script completed successfully.
exit /b 0