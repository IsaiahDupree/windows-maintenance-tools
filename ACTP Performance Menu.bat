@echo off
setlocal EnableExtensions
set "TOOLS_DIR=%~dp0"
set "REPORTS_DIR=%TOOLS_DIR%reports"
if not exist "%REPORTS_DIR%" mkdir "%REPORTS_DIR%"

:menu
cls
echo ACTP Performance Menu
echo =====================
echo.
echo 1. Show top CPU processes
echo 2. Show top RAM processes
echo 3. Run bounded performance report
echo 4. Clear user temp files
echo 5. Close common background apps after confirmation
echo 6. Kill a stuck process by PID after confirmation
echo 7. Set Windows High Performance power plan
echo 8. Exit
echo.
set /p choice=Choose an option: 

if "%choice%"=="1" goto topcpu
if "%choice%"=="2" goto topram
if "%choice%"=="3" goto report
if "%choice%"=="4" goto temp
if "%choice%"=="5" goto background
if "%choice%"=="6" goto killpid
if "%choice%"=="7" goto power
if "%choice%"=="8" exit /b 0
goto menu

:topcpu
powershell -NoProfile -ExecutionPolicy Bypass -Command "$n=[Environment]::ProcessorCount; $a=Get-Process|Select Id,ProcessName,CPU,WorkingSet64; Start-Sleep 5; $b=Get-Process|Select Id,ProcessName,CPU,WorkingSet64; $h=@{}; $a|%%{$h[$_.Id]=$_}; $b|%%{if($h.ContainsKey($_.Id)){[pscustomobject]@{CPUPercent=[math]::Round((($_.CPU-$h[$_.Id].CPU)/5/$n)*100,1); PID=$_.Id; Process=$_.ProcessName; RAM_MB=[math]::Round($_.WorkingSet64/1MB,1)}}}|Sort CPUPercent,RAM_MB -Desc|Select -First 20|Format-Table -AutoSize"
pause
goto menu

:topram
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 Id,ProcessName,@{n='RAM_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}},@{n='CPU_seconds';e={[math]::Round(($_.CPU -as [double]),1)}} | Format-Table -AutoSize"
pause
goto menu

:report
powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS_DIR%collect-system-report.ps1" -OutputDir "%REPORTS_DIR%" -CpuSeconds 45 -MemoryMB 768
pause
goto menu

:temp
echo This clears files in %TEMP% that are not locked by running apps.
set /p ok=Continue? [y/N] 
if /I not "%ok%"=="y" goto menu
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; Write-Output 'Temp cleanup complete.'"
pause
goto menu

:background
echo This can close common user background apps if they are running.
echo It does not close Windows system processes.
echo Targets: Teams, Discord, Spotify, Steam, EpicGamesLauncher, OneDrive, Creative Cloud, Adobe Desktop Service, Docker Desktop
set /p ok=Close matching apps now? [y/N] 
if /I not "%ok%"=="y" goto menu
powershell -NoProfile -ExecutionPolicy Bypass -Command "$names='ms-teams','Teams','Discord','Spotify','steam','EpicGamesLauncher','OneDrive','Creative Cloud','Adobe Desktop Service','Docker Desktop'; foreach($name in $names){Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {Write-Output ('Stopping ' + $_.ProcessName + ' PID ' + $_.Id); Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue}}"
pause
goto menu

:killpid
powershell -NoProfile -ExecutionPolicy Bypass -Command "$n=[Environment]::ProcessorCount; $a=Get-Process|Select Id,ProcessName,CPU,WorkingSet64; Start-Sleep 3; $b=Get-Process|Select Id,ProcessName,CPU,WorkingSet64; $h=@{}; $a|%%{$h[$_.Id]=$_}; $b|%%{if($h.ContainsKey($_.Id)){[pscustomobject]@{CPUPercent=[math]::Round((($_.CPU-$h[$_.Id].CPU)/3/$n)*100,1); PID=$_.Id; Process=$_.ProcessName; RAM_MB=[math]::Round($_.WorkingSet64/1MB,1)}}}|Sort CPUPercent,RAM_MB -Desc|Select -First 20|Format-Table -AutoSize"
echo.
set /p pid=Enter PID to kill, or blank to cancel: 
if "%pid%"=="" goto menu
set /p ok=Kill PID %pid%? [y/N] 
if /I not "%ok%"=="y" goto menu
taskkill /PID %pid% /F
pause
goto menu

:power
powercfg /setactive SCHEME_MIN
echo Requested High Performance power plan. If this failed, run this menu as Administrator.
pause
goto menu
