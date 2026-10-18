@echo off
setlocal EnableExtensions
cls
echo ACTP Process Snapshot
echo =====================
echo.
echo Sampling live CPU for 8 seconds...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$n=[Environment]::ProcessorCount; $a=Get-Process|Select Id,ProcessName,CPU,WorkingSet64; Start-Sleep 8; $b=Get-Process|Select Id,ProcessName,CPU,WorkingSet64; $h=@{}; $a|%%{$h[$_.Id]=$_.CPU}; $b|%%{if($h.ContainsKey($_.Id)){[pscustomobject]@{CPUPercent=[math]::Round((($_.CPU-$h[$_.Id])/8/$n)*100,1); PID=$_.Id; Process=$_.ProcessName; RAM_MB=[math]::Round($_.WorkingSet64/1MB,1)}}}|Sort CPUPercent,RAM_MB -Desc|Select -First 25|Format-Table -AutoSize"
echo.
echo Top RAM processes:
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 Id,ProcessName,@{n='RAM_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}},@{n='CPU_seconds';e={[math]::Round(($_.CPU -as [double]),1)}} | Format-Table -AutoSize"
pause
