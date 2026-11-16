@echo off
setlocal

set "CLICKER=C:\Develop\Clicker\Win32\Release\Clicker.exe"
set "SCRIPT_DIR=C:\Scripts\4Square SL"
rem Note there is no end slash

rem This is all of the scripts that will be run in this test suite
for %%S in (
    "Normal sale - 4Square.script"
    "Suspend trans.script"
    "Recalled item.script"
    "Age restricted (allow).script"
    "Item over limit.script"
    "Unknown item.script"
    "Check digit incorrect.script"
    "Split payment.script"

) do (
    if not exist "%SCRIPT_DIR%\%%~S" (
        echo Error: Script not found: "%SCRIPT_DIR%\%%~S"
        exit /b 2
    )

    echo Running "%SCRIPT_DIR%\%%~S"

    "%CLICKER%" --console "%SCRIPT_DIR%\%%~S"
    if errorlevel 1 (
        echo Error: Script "%%~S" failed.
        exit /b 1
    )
)

echo All scripts completed successfully.
exit /b 0