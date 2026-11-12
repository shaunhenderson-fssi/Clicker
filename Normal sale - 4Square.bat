    @echo off
    setlocal

    set "CLICKER=C:\Develop\Clicker\Win32\Release\Clicker.exe"
    set "SCRIPT=C:\Scripts\4Square SL\Normal sale - 4Square.script"

    "%CLICKER%" --console "%SCRIPT%"
    if errorlevel 1 (
        echo Script failed. Check the script and try again.
        exit /b 1
    )

    echo Script completed successfully.
    exit /b 0