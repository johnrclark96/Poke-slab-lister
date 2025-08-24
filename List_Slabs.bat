@echo off
setlocal ENABLEDELAYEDEXPANSION

REM =======================
REM  USER CONFIG (YOUR APP)
REM =======================
set "EBAY_CLIENT_ID=JohnClar-p-PRD-c8135f6e7-528be997"
set "EBAY_CLIENT_SECRET=PRD-8135f6e740de-933c-4107-8bdb-01b0"
set "EBAY_REFRESH_TOKEN=v^1.1#i^1#r^1#f^0#I^3#p^3#t^Ul4xMF8zOjQzMTUxM0E4OEYzNUUxRTEzNzY2NjFDRURBNURGQkRCXzFfMSNFXjI2MA=="
set "EBAY_RETURN_POLICY_ID=272036672014"

REM =======================
REM  PATHS (EDIT IF NEEDED)
REM =======================
set "BASEDIR=C:\Users\johnr\Documents\ebay"
set "CSV=%BASEDIR%\master.csv"
set "IMGDIR=%BASEDIR%\Images"
set "EPS_SCRIPT=%BASEDIR%\eps_uploader.ps1"
set "LISTER_SCRIPT=%BASEDIR%\lister.ps1"
set "LOGDIR=%BASEDIR%\logs"

if not exist "%BASEDIR%" (echo ERROR: Base directory not found: %BASEDIR%& pause & exit /b 1)
if not exist "%CSV%" (echo ERROR: CSV not found: %CSV%& pause & exit /b 1)
if not exist "%IMGDIR%" (echo ERROR: Images folder not found: %IMGDIR%& pause & exit /b 1)
if not exist "%EPS_SCRIPT%" (echo ERROR: EPS uploader missing: %EPS_SCRIPT%& pause & exit /b 1)
if not exist "%LISTER_SCRIPT%" (echo ERROR: Lister script missing: %LISTER_SCRIPT%& pause & exit /b 1)
if not exist "%LOGDIR%" mkdir "%LOGDIR%"

for /f "tokens=1-3 delims=/ " %%a in ("%date%") do (set d=%%c-%%a-%%b)
for /f "tokens=1-2 delims=: " %%a in ("%time%") do (set t=%%a-%%b)
set "STAMP=%d%_%t%"
set "LOG=%LOGDIR%\run_%STAMP%.log"

echo =============================================== > "%LOG%"
echo  Run started %date% %time% >> "%LOG%"
echo  CSV = %CSV% >> "%LOG%"
echo  IMGDIR = %IMGDIR% >> "%LOG%"
echo =============================================== >> "%LOG%"

REM =======================================================
REM  1) REFRESH ACCESS TOKEN (2h) USING REFRESH TOKEN
REM =======================================================
if "%EBAY_CLIENT_ID%"=="" (echo ERROR: EBAY_CLIENT_ID is blank& pause & exit /b 1)
if "%EBAY_CLIENT_SECRET%"=="" (echo ERROR: EBAY_CLIENT_SECRET is blank& pause & exit /b 1)
if "%EBAY_REFRESH_TOKEN%"=="" (echo ERROR: EBAY_REFRESH_TOKEN is blank& pause & exit /b 1)

for /f "usebackq delims=" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass ^
  -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$pair='${env:EBAY_CLIENT_ID}:${env:EBAY_CLIENT_SECRET}';" ^
  "$basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair));" ^
  "$headers=@{ Authorization='Basic ' + $basic };" ^
  "$scope='https://api.ebay.com/oauth/api_scope https://api.ebay.com/oauth/api_scope/sell.inventory https://api.ebay.com/oauth/api_scope/sell.account https://api.ebay.com/oauth/api_scope/sell.fulfillment';" ^
  "$body=@{ grant_type='refresh_token'; refresh_token=$env:EBAY_REFRESH_TOKEN; scope=$scope };" ^
  "$resp=Invoke-RestMethod -Method Post -Uri 'https://api.ebay.com/identity/v1/oauth2/token' -Headers $headers -Body $body -ContentType 'application/x-www-form-urlencoded';" ^
  "[Console]::Out.Write($resp.access_token)"`) do (
    set "ACCESS_TOKEN=%%A"
)

if "%ACCESS_TOKEN%"=="" (
  echo ERROR: Failed to obtain access token from refresh token. See log for details.
  echo OAuth refresh failed >> "%LOG%"
  pause & exit /b 1
)

REM Export token + common vars so PowerShell scripts can read them
set "ACCESS_TOKEN=%ACCESS_TOKEN%"
if "%EBAY_PAYMENT_POLICY_ID%"=="" set EBAY_PAYMENT_POLICY_ID=272036644014
if "%EBAY_FULFILLMENT_POLICY_ID%"=="" set EBAY_FULFILLMENT_POLICY_ID=272036663014
if "%EBAY_LOCATION_ID%"=="" set EBAY_LOCATION_ID=POKESLABS_US
set "CSV_PATH=%CSV%"
set "IMAGES_DIR=%IMGDIR%"

echo.
echo === Step 1: Uploading images to EPS and writing URLs into the CSV ===
powershell -NoProfile -ExecutionPolicy Bypass ^
  -File "%EPS_SCRIPT%" -CsvPath "%CSV%" 1>>"%LOG%" 2>>&1
if errorlevel 1 (
  echo EPS upload failed. See log: %LOG%
  pause & exit /b 1
)

echo.
echo === Step 2: Creating inventory items, offers, and publishing ===
powershell -NoProfile -ExecutionPolicy Bypass ^
  -File "%LISTER_SCRIPT%" -CsvPath "%CSV%" 1>>"%LOG%" 2>>&1
if errorlevel 1 (
  echo Listing step failed. See log: %LOG%
  pause & exit /b 1
)

echo.
echo All done. Log saved to: %LOG%
pause
endlocal
