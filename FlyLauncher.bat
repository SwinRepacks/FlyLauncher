@echo off
chcp 65001 >nul
title FlyVisuals Bypass Setup
setlocal EnableExtensions

echo ============================================
echo   FlyVisuals Bypass - Auto Setup
echo ============================================
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Перезапускаю с правами администратора...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
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

if not exist "%MITM_CA%" (
    echo [*] Генерирую CA...
    start /b "" mitmdump -p 18765
    timeout /t 3 /nobreak >nul
    taskkill /f /im mitmdump.exe >nul 2>&1
    timeout /t 2 /nobreak >nul
)
if not exist "%MITM_CA%" ( echo [ОШИБКА] CA не создался & pause & exit /b 1 )
echo [OK] CA найден

echo [*] Устанавливаю CA...
certutil -addstore -f root "%MITM_CA_CER%" >nul 2>&1
certutil -addstore -f root "%MITM_CA%" >nul 2>&1
echo [OK] CA установлен

:: Убиваем лаунчер если запущен
echo [*] Закрываю лаунчер если запущен...
taskkill /f /im FlyLauncher.exe >nul 2>&1
timeout /t 2 /nobreak >nul

:: Бекап
if not exist "%ASAR%.original.bak" (
    echo [*] Создаю бекап...
    copy "%ASAR%" "%ASAR%.original.bak" >nul
    echo [OK] Бекап создан
) else (
    echo [SKIP] Бекап уже есть
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

:: Патч 1: net.fetch
echo [*] Патч 1: net.fetch...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%MAIN_JS%';" ^
  "$c=Get-Content -LiteralPath $p -Raw -Encoding UTF8;" ^
  "if($c -notmatch 'globalThis\.fetch'){" ^
  "  $c=$c -replace 'import \{ app, BrowserWindow, shell, dialog, ipcMain, Menu \} from \"electron\";','import { app, BrowserWindow, shell, dialog, ipcMain, Menu, net } from \"electron\";' + \"`r`n\" + 'globalThis.fetch = (url, opts) => net.fetch(url, opts);';" ^
  "  Set-Content -LiteralPath $p -Value $c -Encoding UTF8 -NoNewline;" ^
  "  Write-Host '[OK] patch 1';" ^
  "}else{Write-Host '[SKIP] patch 1'}"

:: Патч 2: checkVisualsLaunchAccess
echo [*] Патч 2: checkVisualsLaunchAccess...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%MAIN_JS%';" ^
  "$c=Get-Content -LiteralPath $p -Raw -Encoding UTF8;" ^
  "$needle='необходима действующая подписка';" ^
  "if($c.Contains($needle)){" ^
  "  $old='async function checkVisualsLaunchAccess\(request\) \{\r?\n[\s\S]*?return token;\r?\n\}';" ^
  "  $new='async function checkVisualsLaunchAccess(request) {`r`n  if (request.versionId !== \"flyvisuals\" && request.flyVisuals !== true) return void 0;`r`n  const token = request.session?.presenceAccessToken;`r`n  if (!token) throw new Error(\"Войдите в аккаунт, чтобы запустить FlyVisuals\");`r`n  return token;`r`n}';" ^
  "  $c=[regex]::Replace($c,$old,$new);" ^
  "  Set-Content -LiteralPath $p -Value $c -Encoding UTF8 -NoNewline;" ^
  "  Write-Host '[OK] patch 2';" ^
  "}else{Write-Host '[SKIP] patch 2'}"

:: Патч 3: getVisualsVmPass
echo [*] Патч 3: vm-pass...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p='%MAIN_JS%';" ^
  "$c=Get-Content -LiteralPath $p -Raw -Encoding UTF8;" ^
  "if($c.Contains('v1/visuals/vm-pass')){" ^
  "  $old='async function getVisualsVmPass\(accessToken\) \{[\s\S]*?return pass\.token;\r?\n\}';" ^
  "  $new='async function getVisualsVmPass(accessToken) {`r`n  return \"fly-bypass-pass-token-2099\";`r`n}';" ^
  "  $c=[regex]::Replace($c,$old,$new);" ^
  "  Set-Content -LiteralPath $p -Value $c -Encoding UTF8 -NoNewline;" ^
  "  Write-Host '[OK] patch 3';" ^
  "}else{Write-Host '[SKIP] patch 3'}"

:: Патч 4: renderer
echo [*] Патч 4: renderer...
set "RJS="
for /f "delims=" %%R in ('dir /b "%EXTRACT_DIR%\out\renderer\assets\index-*.js" 2^>nul') do (
    if not defined RJS set "RJS=%EXTRACT_DIR%\out\renderer\assets\%%R"
)
if defined RJS (
    echo [DEBUG] RJS: %RJS%
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$p='%RJS%';" ^
      "$c=Get-Content -LiteralPath $p -Raw -Encoding UTF8;" ^
      "$needle='необходима действующая подписка';" ^
      "if($c.Contains($needle)){" ^
      "  $old='  let subscriptions;[\s\S]*?if \(!hasAccess\) throw new Error\(\"Для запуска FlyVisuals необходима действующая подписка\"\);\r?\n';" ^
      "  $c=[regex]::Replace($c,$old,'');" ^
      "  Set-Content -LiteralPath $p -Value $c -Encoding UTF8 -NoNewline;" ^
      "  Write-Host '[OK] patch 4';" ^
      "}else{Write-Host '[SKIP] patch 4'}"
) else ( echo [WARN] renderer не найден )

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

:: fly_bypass.py
echo [*] Создаю fly_bypass.py...
(
echo import json
echo from mitmproxy import http
echo.
echo def response^(flow: http.HTTPFlow^):
echo     if "api.flylauncher.net" not in flow.request.pretty_host:
echo         return
echo     path = flow.request.path
echo     if "/v1/visuals/subscriptions" in path and flow.request.method == "GET":
echo         fake = [{"productSlug": "fly-visuals", "active": True, "currentPeriodEnd": "2099-12-31T00:00:00.000Z", "status": "active"}]
echo         flow.response = http.Response.make^(200, json.dumps^(fake^), {"Content-Type": "application/json"}^)
echo         return
echo     if "/v1/visuals/vm-pass" in path and flow.request.method == "POST":
echo         fake = {"token": "bypass-token-2099", "expiresAt": "2099-12-31T00:00:00.000Z", "ttlSeconds": 86400}
echo         flow.response = http.Response.make^(200, json.dumps^(fake^), {"Content-Type": "application/json"}^)
echo         return
echo     if flow.response and flow.response.status_code in ^(401, 403^):
echo         flow.response.status_code = 200
echo         flow.response.content = json.dumps^({"valid": True, "status": "ok"}^).encode^(^)
) > "%BYPASS_PY%"
echo [OK] fly_bypass.py создан

:: Запуск mitmdump
echo [*] Запускаю mitmdump...
start "" /min cmd /c "mitmdump --allow-hosts api\.flylauncher\.net -s \"%BYPASS_PY%\" -p 8080"
timeout /t 2 /nobreak >nul

:: Запуск лаунчера
echo [*] Запускаю FlyLauncher...
start "" "%LAUNCHER_DIR%\FlyLauncher.exe" --proxy-server="127.0.0.1:8080"

echo.
echo ============================================
echo   Готово! Жми "Играть" в разделе Визуалы.
echo ============================================
pause
endlocal