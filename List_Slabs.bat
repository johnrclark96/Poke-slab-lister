@echo off
setlocal ENABLEDELAYEDEXPANSION

set "SECRETS=C:\Users\johnr\Documents\ebay\secrets.env"
if not exist "%SECRETS%" (
  echo ERROR: secrets file not found: %SECRETS%
  pause & exit /b 1
)
for /f "usebackq tokens=1* delims== eol=#" %%A in ("%SECRETS%") do set "%%A=%%B"

if "%EBAY_ENV%"=="" set EBAY_ENV=test

set "BASEDIR=C:\Users\johnr\Documents\ebay"
set "CSV=%BASEDIR%\master.csv"
set "IMGDIR=%BASEDIR%\Images"
set "EPS_SCRIPT=%BASEDIR%\eps_uploader.ps1"
set "LISTER_SCRIPT=%BASEDIR%\lister.ps1"
set "LOGDIR=%BASEDIR%\logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

for /f "tokens=1-3 delims=/ " %%a in ("%date%") do (set d=%%c-%%a-%%b)
for /f "tokens=1-2 delims=: " %%a in ("%time%") do (set t=%%a-%%b)
set "LOG=%LOGDIR%\run_%d%_%t%.log"

set "PSARGS=-CsvPath \"%CSV%\""
if /I "%1"=="live" (
  set "PSARGS=%PSARGS% -Live"
) else (
  set "PSARGS=%PSARGS% -DryRun"
)

if /I "%1"=="live" (
  if "%EBAY_CLIENT_ID%"=="" (echo ERROR: EBAY_CLIENT_ID missing & exit /b 1)
  if "%EBAY_CLIENT_SECRET%"=="" (echo ERROR: EBAY_CLIENT_SECRET missing & exit /b 1)
  if "%EBAY_REFRESH_TOKEN%"=="" (echo ERROR: EBAY_REFRESH_TOKEN missing & exit /b 1)
  for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass ^
    -Command "$pair='${env:EBAY_CLIENT_ID}:${env:EBAY_CLIENT_SECRET}';" ^
    "$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair));" ^
    "$headers=@{Authorization='Basic '+$basic};" ^
    "$scope='https://api.ebay.com/oauth/api_scope https://api.ebay.com/oauth/api_scope/sell.inventory https://api.ebay.com/oauth/api_scope/sell.account https://api.ebay.com/oauth/api_scope/sell.fulfillment';" ^
    "$body=@{grant_type='refresh_token';refresh_token=$env:EBAY_REFRESH_TOKEN;scope=$scope};" ^
    "$resp=Invoke-RestMethod -Method Post -Uri 'https://api.ebay.com/identity/v1/oauth2/token' -Headers $headers -Body $body -ContentType 'application/x-www-form-urlencoded';" ^
    "[Console]::Out.Write($resp.access_token)"`) do set "ACCESS_TOKEN=%%A"
  if "%ACCESS_TOKEN%"=="" (echo ERROR: failed to obtain access token & exit /b 1)
) else (
  set "ACCESS_TOKEN=dummy"
)

set "CSV_PATH=%CSV%"
set "IMAGES_DIR=%IMGDIR%"

echo === Uploading images ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%EPS_SCRIPT%" %PSARGS% 1>>"%LOG%" 2>>&1
if errorlevel 1 (
  echo EPS upload failed. See log: %LOG%
  exit /b 1
)

echo === Creating listings ===
powershell -NoProfile -ExecutionPolicy Bypass -File "%LISTER_SCRIPT%" %PSARGS% 1>>"%LOG%" 2>>&1
if errorlevel 1 (
  echo Listing step failed. See log: %LOG%
  exit /b 1
)

echo Done. Log: %LOG%
endlocal
