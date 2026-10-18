@echo off
setlocal EnableExtensions
set "TOOLS_DIR=%~dp0"
set "LOG_DIR=%TOOLS_DIR%reports"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "LOG_FILE=%LOG_DIR%\quick-clear-%DATE:/=-%-%TIME::=-%.log"
set "LOG_FILE=%LOG_FILE: =0%"

echo ACTP Quick Clear Processing
echo ===========================
echo.
echo This will clear user temp files and can close common background apps.
echo It will not stop Windows system processes.
echo.

echo Clearing user temp files...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; Write-Output ('Temp cleanup complete at ' + (Get-Date).ToString('s'))" >> "%LOG_FILE%" 2>&1

echo.
echo Optional background-app close list:
echo Teams, Discord, Spotify, Steam, EpicGamesLauncher, Docker Desktop,
echo Creative Cloud UI Helper, Adobe Desktop Service.
echo.
set /p ok=Close those matching background apps now? [y/N] 
if /I "%ok%"=="y" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$names='ms-teams','Teams','Discord','Spotify','steam','EpicGamesLauncher','Docker Desktop','Creative Cloud UI Helper','Adobe Desktop Service'; foreach($name in $names){Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {Write-Output ('Stopping ' + $_.ProcessName + ' PID ' + $_.Id); Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue}}" >> "%LOG_FILE%" 2>&1
)

echo.
echo Current top CPU processes:
powershell -NoProfile -ExecutionPolicy Bypass -Command "$n=[Environment]::ProcessorCount; $a=Get-Process|Select Id,ProcessName,CPU,WorkingSet64; Start-Sleep 5; $b=Get-Process|Select Id,ProcessName,CPU,WorkingSet64; $h=@{}; $a|%%{$h[$_.Id]=$_.CPU}; $b|%%{if($h.ContainsKey($_.Id)){[pscustomobject]@{CPUPercent=[math]::Round((($_.CPU-$h[$_.Id])/5/$n)*100,1); PID=$_.Id; Process=$_.ProcessName; RAM_MB=[math]::Round($_.WorkingSet64/1MB,1)}}}|Sort CPUPercent,RAM_MB -Desc|Select -First 15|Format-Table -AutoSize"

echo.
echo Done. Log: %LOG_FILE%
pause
