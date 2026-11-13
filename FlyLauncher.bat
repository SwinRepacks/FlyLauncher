@echo off
chcp 65001 >nul
title FlyVisuals Bypass Setup
setlocal EnableExtensions DisableDelayedExpansion

echo ============================================
echo   FlyVisuals Bypass - Auto Setup
echo ============================================
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Перезапускаю с правами администратора...
    powershell -Command "Start-Process -FilePath cmd -ArgumentList '/k', '\"%~f0\"' -Verb RunAs"
    exit /b
)

set "LAUNCHER_DIR=%LOCALAPPDATA%\Programs\flylauncher"
set "RESOURCES=%LAUNCHER_DIR%\resources"
set "ASAR=%RESOURCES%\app.asar"
set "EXTRACT_DIR=%TEMP%\fly_bypass_src"
set "BYPASS_DIR=%~dp0"
set "BYPASS_PY=%BYPASS_DIR%fly_bypass.py"
set "MITM_CA=%USERPROFILE%\.mitmproxy\mitmproxy-ca-cert.pem"
set "MITM_CA_CER=%USERPROFILE%\.mitmproxy\mitmproxy-ca-cert.cer"
set "MC_DIR=%APPDATA%\.minecraft"

echo [DEBUG] ASAR: %ASAR%
echo [DEBUG] Extract: %EXTRACT_DIR%
echo.

if not exist "%ASAR%" (
    echo [ОШИБКА] FlyLauncher не найден: %ASAR%
    pause & exit /b 1
)
echo [OK] Лаунчер найден

where mitmdump >nul 2>&1
if %errorLevel% neq 0 ( echo [ОШИБКА] mitmproxy не найден & pause & exit /b 1 )
echo [OK] mitmproxy найден

where asar >nul 2>&1
if %errorLevel% neq 0 (
    echo [*] Устанавливаю asar...
    npm install -g @electron/asar
    if %errorLevel% neq 0 ( echo [ОШИБКА] npm не найден & pause & exit /b 1 )
)
echo [OK] asar найден

:: Убиваем старые зависшие процессы
taskkill /f /im mitmdump.exe >nul 2>&1
timeout /t 1 /nobreak >nul

:: ============================================================
:: Генерация CA
:: ============================================================
if exist "%MITM_CA%" goto :ca_ready

echo [*] Проверяю, свободен ли порт 18765...
netstat -ano | findstr ":18765" >nul 2>&1
if not errorlevel 1 (
    echo [!] Порт 18765 занят. Пробую освободить...
    for /f "tokens=5" %%P in ('netstat -ano ^| findstr ":18765"') do (
        taskkill /f /pid %%P >nul 2>&1
    )
    timeout /t 2 /nobreak >nul
)

echo [*] Генерирую CA (жду 10 секунд)...
start "" /b mitmdump -p 18765
timeout /t 10 /nobreak >nul
taskkill /f /im mitmdump.exe >nul 2>&1
timeout /t 2 /nobreak >nul

if not exist "%MITM_CA%" (
    echo [ОШИБКА] CA не создался.
    pause & exit /b 1
)

:ca_ready
echo [OK] CA найден

echo [*] Устанавливаю CA...
certutil -addstore -f root "%MITM_CA_CER%" >nul 2>&1
certutil -addstore -f root "%MITM_CA%" >nul 2>&1
echo [OK] CA установлен

:: Убиваем лаунчер если запущен
echo [*] Закрываю лаунчер если запущен...
taskkill /f /im FlyLauncher.exe >nul 2>&1
timeout /t 2 /nobreak >nul

:: ============================================================
:: Восстановление ASAR
:: ============================================================
if exist "%ASAR%.original.bak" (
    echo [*] Восстанавливаю оригинальный ASAR из бекапа...
    copy /y "%ASAR%.original.bak" "%ASAR%" >nul
    echo [OK] Оригинал восстановлен
) else (
    echo [*] Создаю бекап...
    copy "%ASAR%" "%ASAR%.original.bak" >nul
    echo [OK] Бекап создан
)

:: Распаковка
echo [*] Распаковываю ASAR...
if exist "%EXTRACT_DIR%" (
    echo [*] Удаляю старую распаковку...
    rd /s /q "%EXTRACT_DIR%"
    timeout /t 1 /nobreak >nul
)
echo [*] Запускаю asar extract...
cmd /c asar extract "%ASAR%" "%EXTRACT_DIR%"
set ASAR_ERR=%errorLevel%
echo [DEBUG] asar extract errorLevel: %ASAR_ERR%
if %ASAR_ERR% neq 0 (
    echo [ОШИБКА] asar extract провалился с кодом %ASAR_ERR%
    pause & exit /b 1
)
if not exist "%EXTRACT_DIR%\out\main\index.js" (
    echo [ОШИБКА] index.js не найден после распаковки
    pause & exit /b 1
)
echo [OK] ASAR распакован

set "MAIN_JS=%EXTRACT_DIR%\out\main\index.js"
set "RJS="
for /f "delims=" %%R in ('dir /b "%EXTRACT_DIR%\out\renderer\assets\index-*.js" 2^>nul') do (
    if not defined RJS set "RJS=%EXTRACT_DIR%\out\renderer\assets\%%R"
)

:: ============================================================
:: Применение патчей через Node.js
:: ============================================================
echo [*] Применяю патчи...
set "PATCH_JS=%TEMP%\fly_patch.js"
> "%PATCH_JS%" echo const fs = require('fs');
>> "%PATCH_JS%" echo const mainPath = process.argv[2];
>> "%PATCH_JS%" echo const rendererPath = process.argv[3];
>> "%PATCH_JS%" echo.
>> "%PATCH_JS%" echo function patch(file, type) {
>> "%PATCH_JS%" echo     if (!fs.existsSync(file)) return;
>> "%PATCH_JS%" echo     let content = fs.readFileSync(file, 'utf8');
>> "%PATCH_JS%" echo     if (type === 'main') {
>> "%PATCH_JS%" echo         if (content.includes('import { app, BrowserWindow, shell, dialog, ipcMain, Menu } from "electron";')) {
>> "%PATCH_JS%" echo             content = content.replace('import { app, BrowserWindow, shell, dialog, ipcMain, Menu } from "electron";', 'import { app, BrowserWindow, shell, dialog, ipcMain, Menu, net } from "electron";\nglobalThis.fetch = (url, opts) =^> net.fetch(url, opts);');
>> "%PATCH_JS%" echo             console.log('[OK] patch 1');
>> "%PATCH_JS%" echo         } else if (!content.includes('globalThis.fetch')) {
>> "%PATCH_JS%" echo             content = 'import { net } from "electron";\nglobalThis.fetch = (url, opts) =^> net.fetch(url, opts);\n' + content;
>> "%PATCH_JS%" echo             console.log('[OK] patch 1 (fallback)');
>> "%PATCH_JS%" echo         } else {
>> "%PATCH_JS%" echo             console.log('[SKIP] patch 1');
>> "%PATCH_JS%" echo         }
>> "%PATCH_JS%" echo         const checkFnRegex = /async function checkVisualsLaunchAccess\(request\)\s*\{[\s\S]*?return token;\s*\}/g;
>> "%PATCH_JS%" echo         if (checkFnRegex.test(content)) {
>> "%PATCH_JS%" echo             content = content.replace(checkFnRegex, 'async function checkVisualsLaunchAccess(request) {\n  if (request.versionId !== "flyvisuals" ^&^& request.flyVisuals !== true) return void 0;\n  const token = request.session?.presenceAccessToken;\n  if (!token) throw new Error("Войдите в аккаунт, чтобы запустить FlyVisuals");\n  return token;\n}');
>> "%PATCH_JS%" echo             console.log('[OK] patch 2');
>> "%PATCH_JS%" echo         } else {
>> "%PATCH_JS%" echo             console.log('[SKIP] patch 2');
>> "%PATCH_JS%" echo         }
>> "%PATCH_JS%" echo         const vmPassRegex = /async function getVisualsVmPass\(accessToken\)\s*\{[\s\S]*?return pass\.token;\s*\}/g;
>> "%PATCH_JS%" echo         if (vmPassRegex.test(content)) {
>> "%PATCH_JS%" echo             content = content.replace(vmPassRegex, 'async function getVisualsVmPass(accessToken) {\n  return "fly-bypass-pass-token-2099";\n}');
>> "%PATCH_JS%" echo             console.log('[OK] patch 3');
>> "%PATCH_JS%" echo         } else {
>> "%PATCH_JS%" echo             console.log('[SKIP] patch 3');
>> "%PATCH_JS%" echo         }
>> "%PATCH_JS%" echo     }
>> "%PATCH_JS%" echo     if (type === 'renderer') {
>> "%PATCH_JS%" echo         const throwRegex = /if\s*\(!hasAccess\)\s*throw new Error\("Для запуска FlyVisuals необходима действующая подписка"\);/g;
>> "%PATCH_JS%" echo         if (throwRegex.test(content)) {
>> "%PATCH_JS%" echo             content = content.replace(throwRegex, 'if (!hasAccess) { /* bypassed */ }');
>> "%PATCH_JS%" echo             console.log('[OK] patch 4');
>> "%PATCH_JS%" echo         } else {
>> "%PATCH_JS%" echo             console.log('[SKIP] patch 4');
>> "%PATCH_JS%" echo         }
>> "%PATCH_JS%" echo     }
>> "%PATCH_JS%" echo     fs.writeFileSync(file, content, 'utf8');
>> "%PATCH_JS%" echo }
>> "%PATCH_JS%" echo if (mainPath) patch(mainPath, 'main');
>> "%PATCH_JS%" echo if (rendererPath ^&^& rendererPath !== 'none') patch(rendererPath, 'renderer');

node "%PATCH_JS%" "%MAIN_JS%" "%RJS%"
if %errorLevel% neq 0 (
    echo [ОШИБКА] Патчинг провалился.
    pause & exit /b 1
)
del "%PATCH_JS%"

:: flyvisuals.json
echo [*] flyvisuals.json...
if not exist "%MC_DIR%\versions\flyvisuals" mkdir "%MC_DIR%\versions\flyvisuals"
if not exist "%MC_DIR%\versions\flyvisuals\flyvisuals.json" (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "try{Invoke-WebRequest -Uri 'https://files.flyvisuals.net/releases/stable/flyvisuals.json' -OutFile '%MC_DIR%\versions\flyvisuals\flyvisuals.json' -TimeoutSec 20; Write-Host '[OK] downloaded'}catch{Write-Host '[WARN]' $_.Exception.Message}"
) else ( echo [SKIP] flyvisuals.json уже есть )

:: Перепаковка
echo [*] Перепаковываю ASAR...
cmd /c asar pack "%EXTRACT_DIR%" "%ASAR%"
set PACK_ERR=%errorLevel%
echo [DEBUG] asar pack errorLevel: %PACK_ERR%
if %PACK_ERR% neq 0 (
    echo [ОШИБКА] asar pack провалился
    pause & exit /b 1
)
echo [OK] ASAR перепакован

:: ============================================================
:: ГЕНЕРАЦИЯ fly_bypass.py (ТОЛЬКО ПОДПИСКА)
:: ============================================================
echo [*] Создаю fly_bypass.py (только обход подписки)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$lines = @(" ^
  "'import json'," ^
  "'from mitmproxy import http'," ^
  "''," ^
  "'def response(flow: http.HTTPFlow):'," ^
  "'    if ''api.flylauncher.net'' not in flow.request.pretty_host:'," ^
  "'        return'," ^
  "'    if not flow.response:'," ^
  "'        return'," ^
  "'    path = flow.request.path'," ^
  "''," ^
  "'    if ''heartbeat'' in path or ''telemetry'' in path or ''presence'' in path:'," ^
  "'        return'," ^
  "''," ^
  "'    if ''/v1/visuals/subscriptions'' in path and flow.request.method == ''GET'':'," ^
  "'        flow.response.status_code = 200'," ^
  "'        flow.response.content = json.dumps([{''productSlug'': ''fly-visuals'', ''active'': True, ''currentPeriodEnd'': ''2099-12-31T00:00:00.000Z'', ''status'': ''active''}]).encode()'," ^
  "'        return'," ^
  "''," ^
  "'    if ''/v1/visuals/vm-pass'' in path and flow.request.method == ''POST'':'," ^
  "'        flow.response.status_code = 200'," ^
  "'        flow.response.content = json.dumps({''token'': ''bypass-token-2099'', ''expiresAt'': ''2099-12-31T00:00:00.000Z'', ''ttlSeconds'': 86400}).encode()'," ^
  "'        return'," ^
  "''," ^
  "'    if flow.response and flow.response.status_code in (401, 403):'," ^
  "'        flow.response.status_code = 200'," ^
  "'        flow.response.content = json.dumps({''valid'': True, ''status'': ''ok''}).encode()'" ^
  "); Set-Content -Path '%BYPASS_PY%' -Value $lines -Encoding UTF8"

echo [OK] fly_bypass.py создан

:: Запуск mitmdump
echo [*] Запускаю mitmdump...
start "MitmProxy" cmd /k "mitmdump -p 8080 -s \"%BYPASS_PY%\""
timeout /t 5 /nobreak >nul

:: Запуск лаунчера
echo [*] Запускаю FlyLauncher...
start "" "%LAUNCHER_DIR%\FlyLauncher.exe" --proxy-server="127.0.0.1:8080"

echo.
echo ============================================
echo   Готово! Жми "Играть" в разделе Визуалы.
echo ============================================
pause
endlocal
