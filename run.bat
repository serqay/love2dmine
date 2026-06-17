@echo off
echo Starting Minecraft Love2D...

:: Указываем ваш конкретный путь к Love2D
set LOVE_PATH="D:\LOVE\love.exe"

if exist %LOVE_PATH% (
    echo Love2D found at %LOVE_PATH%
    %LOVE_PATH% .
    exit /b
) else (
    echo.
    echo Error: Love2D was not found at %LOVE_PATH%
    echo Please check if the path is correct or if love.exe was moved.
    echo.
    pause
)
