@echo off
setlocal
title FlyVisuals Bypass - Dependency Installer

net session >nul 2>&1
if %errorLevel% neq 0 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set "TEMP_DIR=%TEMP%\fly_setup"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

echo ============================================
echo   Installing Dependencies
echo ============================================

:: 1. Node.js
where node >nul 2>&1
if %errorLevel% equ 0 goto node_ok

echo.
echo [!] Node.js not found. Downloading...
powershell -Command "Invoke-WebRequest -Uri 'https://nodejs.org/dist/v20.11.0/node-v20.11.0-x64.msi' -OutFile '%TEMP_DIR%\node.msi'"
echo [*] Installing Node.js...
msiexec /i "%TEMP_DIR%\node.msi" /qn /norestart
set "PATH=%ProgramFiles%\nodejs;%PATH%"
:node_ok
echo [OK] Node.js ready

:: 2. mitmproxy
where mitmdump >nul 2>&1
if %errorLevel% equ 0 goto mitm_ok

echo.
echo [!] mitmproxy not found. Downloading...
powershell -Command "Invoke-WebRequest -Uri 'https://downloads.mitmproxy.org/10.3.1/mitmproxy-10.3.1-windows-x86_64.zip' -OutFile '%TEMP_DIR%\mitm.zip'"
if not exist "%TEMP_DIR%\mitm.zip" (
    echo [ERROR] Failed to download mitmproxy.
    pause
    exit /b
)

echo [*] Extracting mitmproxy to C:\Program Files\mitmproxy...
powershell -Command "Expand-Archive -Path '%TEMP_DIR%\mitm.zip' -DestinationPath 'C:\Program Files\mitmproxy' -Force"
set "PATH=C:\Program Files\mitmproxy;%PATH%"
:mitm_ok
echo [OK] mitmproxy ready

:: 3. asar
where asar >nul 2>&1
if %errorLevel% equ 0 goto asar_ok

echo.
echo [!] asar not found. Installing via npm...
call npm install -g @electron/asar
:asar_ok
echo [OK] asar ready

echo.
echo ============================================
echo   Installation Complete!
echo ============================================
pause