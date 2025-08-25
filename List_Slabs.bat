@echo off
setlocal ENABLEDELAYEDEXPANSION
REM Ensure we run from the script directory
cd /d "%~dp0"

set "SECRETS=%~dp0secrets.env"
if not exist "%SECRETS%" (
  echo ERROR: secrets file not found: %SECRETS%
  exit /b 1
)
for /f "usebackq tokens=1* delims== eol=#" %%A in ("%SECRETS%") do set "%%A=%%B"

for %%V in (EBAY_CLIENT_ID EBAY_CLIENT_SECRET EBAY_REFRESH_TOKEN EBAY_LOCATION_ID EBAY_PAYMENT_POLICY_ID EBAY_RETURN_POLICY_ID EBAY_FULFILLMENT_POLICY_ID) do (
  if not defined %%V (
    echo ERROR: %%V missing in %SECRETS%
    exit /b 1
  )
)

if "%EBAY_ENV%"=="" set EBAY_ENV=test
if "%BASEDIR%"=="" set "BASEDIR=C:\Users\johnr\Documents\ebay"
if "%LISTING_FORMAT%"=="" set "LISTING_FORMAT=AUCTION"

set "CSV=%BASEDIR%\master.csv"
set "IMGDIR=%BASEDIR%\Images"
set "LOGDIR=%BASEDIR%\logs"
set "OUTMAP=%BASEDIR%\eps_image_map.json"
set "PULL_SCRIPT=%~dp0Pull-Photos-FromMasterCSV.ps1"
set "EPS_SCRIPT=%~dp0eps_uploader.ps1"
set "LISTER_SCRIPT=%~dp0lister.ps1"

if not exist "%CSV%" (
  echo ERROR: master.csv not found at %CSV%
  exit /b 1
)
if not exist "%IMGDIR%" (
  echo ERROR: Images directory not found at %IMGDIR%
  exit /b 1
)
if not exist "%PULL_SCRIPT%" (
  echo ERROR: missing Pull-Photos-FromMasterCSV.ps1
  exit /b 1
)
if not exist "%EPS_SCRIPT%" (
  echo ERROR: missing eps_uploader.ps1
  exit /b 1
)
if not exist "%LISTER_SCRIPT%" (
  echo ERROR: missing lister.ps1
  exit /b 1
)

if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>&1
for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%I"
set "LOG=%LOGDIR%\run_%STAMP%.log"

set "RUNARGS=-DryRun"
if /I "%1"=="live" set "RUNARGS="

REM Obtain OAuth token when running live
if /I "%1"=="live" (
  powershell -NoProfile -Command "$pair=\"${env:EBAY_CLIENT_ID}:${env:EBAY_CLIENT_SECRET}\"; $basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair)); $headers=@{Authorization=\"Basic $basic\"}; $scope='https://api.ebay.com/oauth/api_scope https://api.ebay.com/oauth/api_scope/sell.inventory https://api.ebay.com/oauth/api_scope/sell.account https://api.ebay.com/oauth/api_scope/sell.fulfillment'; $body=@{grant_type='refresh_token';refresh_token=$env:EBAY_REFRESH_TOKEN;scope=$scope}; try { $resp=Invoke-RestMethod -Method Post -Uri 'https://api.ebay.com/identity/v1/oauth2/token' -Headers $headers -Body $body -ContentType 'application/x-www-form-urlencoded'; $resp.access_token >'$LOGDIR\token.tmp' } catch { $_ | Out-String | Add-Content '$LOG'; exit 1 }" >>"%LOG%" 2>>&1
  if errorlevel 1 goto :failure
  set /p ACCESS_TOKEN=<"%LOGDIR%\token.tmp"
  del "%LOGDIR%\token.tmp"
  if "%ACCESS_TOKEN%"=="" goto :failure
) else (
  set "ACCESS_TOKEN=dummy"
)
call :RunStep "Pull photos" powershell -NoProfile -ExecutionPolicy Bypass -File "%PULL_SCRIPT%" -CsvPath "%CSV%" -DestDir "%IMGDIR%"
if errorlevel 1 goto :failure
call :RunStep "Upload EPS" powershell -NoProfile -ExecutionPolicy Bypass -File "%EPS_SCRIPT%" -CsvPath "%CSV%" -ImagesDir "%IMGDIR%" -AccessToken "%ACCESS_TOKEN%" -OutMap "%OUTMAP%" %RUNARGS%
if errorlevel 1 goto :failure
call :RunStep "Create listings" powershell -NoProfile -ExecutionPolicy Bypass -File "%LISTER_SCRIPT%" -CsvPath "%CSV%" -AccessToken "%ACCESS_TOKEN%" -ImageMap "%OUTMAP%" -ListingFormat "%LISTING_FORMAT%" %RUNARGS%
if errorlevel 1 goto :failure

echo Done. Log: %LOG%
exit /b 0

:RunStep
set "STEP=%~1"
shift
%* >>"%LOG%" 2>>&1
exit /b %errorlevel%

:failure
echo %STEP% failed. See log: %LOG%
exit /b 1
