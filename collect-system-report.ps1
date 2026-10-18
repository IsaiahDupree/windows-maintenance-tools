param(
    [string]$OutputDir = "$env:USERPROFILE\Desktop\ACTP Performance Tools\reports",
    [int]$CpuSeconds = 45,
    [int]$SampleSeconds = 5,
    [int]$MemoryMB = 768,
    [switch]$SkipLoad
)

$ErrorActionPreference = "Continue"

function New-DirectoryIfMissing {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-ProcessCpuSample {
    param(
        [int]$Seconds = 5,
        [int]$Top = 20
    )

    $logicalProcessors = [Environment]::ProcessorCount
    $first = Get-Process | ForEach-Object {
        [pscustomobject]@{
            Id = $_.Id
            ProcessName = $_.ProcessName
            CPU = if ($null -eq $_.CPU) { 0.0 } else { [double]$_.CPU }
            WorkingSetMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
            Path = $_.Path
        }
    }
    Start-Sleep -Seconds $Seconds
    $second = Get-Process | ForEach-Object {
        [pscustomobject]@{
            Id = $_.Id
            ProcessName = $_.ProcessName
            CPU = if ($null -eq $_.CPU) { 0.0 } else { [double]$_.CPU }
            WorkingSetMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
            Path = $_.Path
        }
    }

    $byId = @{}
    foreach ($p in $first) {
        $byId[$p.Id] = $p
    }

    $rows = foreach ($p in $second) {
        if ($byId.ContainsKey($p.Id)) {
            $deltaCpuSeconds = [math]::Max(0, $p.CPU - $byId[$p.Id].CPU)
            [pscustomobject]@{
                Id = $p.Id
                ProcessName = $p.ProcessName
                CpuPercent = [math]::Round(($deltaCpuSeconds / $Seconds / $logicalProcessors) * 100, 1)
                CpuSecondsDelta = [math]::Round($deltaCpuSeconds, 2)
                WorkingSetMB = $p.WorkingSetMB
                Path = $p.Path
            }
        }
    }

    $rows | Sort-Object CpuPercent, WorkingSetMB -Descending | Select-Object -First $Top
}

function Get-SystemSnapshot {
    param([int]$SampleSeconds = 5)

    $cpu = Get-CimInstance Win32_Processor
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        [pscustomobject]@{
            Drive = $_.DeviceID
            FreeGB = [math]::Round($_.FreeSpace / 1GB, 2)
            SizeGB = [math]::Round($_.Size / 1GB, 2)
            FreePercent = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
        }
    }

    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average

    [pscustomobject]@{
        Timestamp = (Get-Date).ToString("s")
        ComputerName = $env:COMPUTERNAME
        UserName = [Environment]::UserName
        OsCaption = $os.Caption
        OsVersion = $os.Version
        UptimeHours = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 2)
        CpuName = ($cpu | Select-Object -First 1).Name
        PhysicalCores = ($cpu | Measure-Object -Property NumberOfCores -Sum).Sum
        LogicalProcessors = [Environment]::ProcessorCount
        CpuLoadPercent = [math]::Round($cpuLoad, 1)
        TotalRamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        FreeRamGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        FreeRamPercent = [math]::Round(($os.FreePhysicalMemory * 1KB / $cs.TotalPhysicalMemory) * 100, 1)
        Disks = $disks
        TopCpuProcesses = @(Get-ProcessCpuSample -Seconds $SampleSeconds -Top 20)
        TopMemoryProcesses = @(Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 Id,ProcessName,@{n="WorkingSetMB";e={[math]::Round($_.WorkingSet64 / 1MB, 1)}},@{n="CPU";e={[math]::Round(($_.CPU -as [double]), 1)}},Path)
    }
}

function Invoke-CpuLoadTest {
    param(
        [int]$Seconds = 45,
        [int]$MemoryMB = 768
    )

    $threads = [Math]::Max(1, [Environment]::ProcessorCount - 1)
    $deadline = (Get-Date).AddSeconds($Seconds)
    $scriptBlock = {
        param($DeadlineTicks)
        $x = 0.0001
        while ((Get-Date).Ticks -lt $DeadlineTicks) {
            for ($i = 0; $i -lt 250000; $i++) {
                $x = [Math]::Sqrt($x + 1.000001)
            }
        }
        return $x
    }

    $buffer = $null
    if ($MemoryMB -gt 0) {
        try {
            $buffer = New-Object byte[] ($MemoryMB * 1MB)
            for ($i = 0; $i -lt $buffer.Length; $i += 4096) {
                $buffer[$i] = 1
            }
        } catch {
            Write-Warning "Memory allocation test failed: $($_.Exception.Message)"
        }
    }

    $jobs = @()
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $threads; $i++) {
        $jobs += Start-Job -ScriptBlock $scriptBlock -ArgumentList $deadline.Ticks
    }

    $samples = @()
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $os = Get-CimInstance Win32_OperatingSystem
        $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        $samples += [pscustomobject]@{
            Timestamp = (Get-Date).ToString("s")
            CpuLoadPercent = [math]::Round($cpuLoad, 1)
            FreeRamGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        }
    }

    Wait-Job -Job $jobs -Timeout 10 | Out-Null
    foreach ($job in $jobs) {
        Receive-Job -Job $job | Out-Null
        Remove-Job -Job $job -Force | Out-Null
    }
    $stopwatch.Stop()
    $buffer = $null
    [GC]::Collect()

    [pscustomobject]@{
        DurationSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        WorkerJobs = $threads
        MemoryTouchedMB = $MemoryMB
        AverageCpuLoadPercent = if ($samples.Count -gt 0) { [math]::Round(($samples | Measure-Object -Property CpuLoadPercent -Average).Average, 1) } else { $null }
        PeakCpuLoadPercent = if ($samples.Count -gt 0) { [math]::Round(($samples | Measure-Object -Property CpuLoadPercent -Maximum).Maximum, 1) } else { $null }
        MinimumFreeRamGB = if ($samples.Count -gt 0) { [math]::Round(($samples | Measure-Object -Property FreeRamGB -Minimum).Minimum, 2) } else { $null }
        Samples = $samples
    }
}

function Write-MarkdownReport {
    param(
        [object]$Report,
        [string]$Path
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# ACTP Windows Performance Report")
    $lines.Add("")
    $lines.Add("Generated: $($Report.GeneratedAt)")
    $lines.Add("Computer: $($Report.Baseline.ComputerName)")
    $lines.Add("User: $($Report.Baseline.UserName)")
    $lines.Add("")
    $lines.Add("## System")
    $lines.Add("")
    $lines.Add("- OS: $($Report.Baseline.OsCaption) $($Report.Baseline.OsVersion)")
    $lines.Add("- CPU: $($Report.Baseline.CpuName)")
    $lines.Add("- Cores/logical processors: $($Report.Baseline.PhysicalCores) / $($Report.Baseline.LogicalProcessors)")
    $lines.Add("- RAM: $($Report.Baseline.TotalRamGB) GB total, $($Report.Baseline.FreeRamGB) GB free at baseline")
    $lines.Add("- Uptime: $($Report.Baseline.UptimeHours) hours")
    $lines.Add("")
    $lines.Add("## Disks")
    $lines.Add("")
    foreach ($disk in $Report.Baseline.Disks) {
        $lines.Add("- $($disk.Drive): $($disk.FreeGB) GB free of $($disk.SizeGB) GB ($($disk.FreePercent)% free)")
    }
    $lines.Add("")
    $lines.Add("## Load Test")
    $lines.Add("")
    if ($null -ne $Report.LoadTest) {
        $lines.Add("- Duration: $($Report.LoadTest.DurationSeconds) seconds")
        $lines.Add("- Worker jobs: $($Report.LoadTest.WorkerJobs)")
        $lines.Add("- Memory touched: $($Report.LoadTest.MemoryTouchedMB) MB")
        $lines.Add("- Average CPU load: $($Report.LoadTest.AverageCpuLoadPercent)%")
        $lines.Add("- Peak CPU load: $($Report.LoadTest.PeakCpuLoadPercent)%")
        $lines.Add("- Minimum free RAM during test: $($Report.LoadTest.MinimumFreeRamGB) GB")
    } else {
        $lines.Add("- Skipped by request.")
    }
    $lines.Add("")
    $lines.Add("## Top CPU Processes Before Load")
    $lines.Add("")
    $lines.Add("| CPU % | PID | Process | RAM MB |")
    $lines.Add("|---:|---:|---|---:|")
    foreach ($p in $Report.Baseline.TopCpuProcesses) {
        $lines.Add("| $($p.CpuPercent) | $($p.Id) | $($p.ProcessName) | $($p.WorkingSetMB) |")
    }
    $lines.Add("")
    $lines.Add("## Top CPU Processes After Load")
    $lines.Add("")
    $lines.Add("| CPU % | PID | Process | RAM MB |")
    $lines.Add("|---:|---:|---|---:|")
    foreach ($p in $Report.AfterLoad.TopCpuProcesses) {
        $lines.Add("| $($p.CpuPercent) | $($p.Id) | $($p.ProcessName) | $($p.WorkingSetMB) |")
    }
    $lines.Add("")
    $lines.Add("## Top Memory Processes After Load")
    $lines.Add("")
    $lines.Add("| RAM MB | PID | Process | CPU seconds |")
    $lines.Add("|---:|---:|---|---:|")
    foreach ($p in $Report.AfterLoad.TopMemoryProcesses | Select-Object -First 15) {
        $lines.Add("| $($p.WorkingSetMB) | $($p.Id) | $($p.ProcessName) | $($p.CPU) |")
    }
    $lines.Add("")
    $lines.Add("## Practical Actions")
    $lines.Add("")
    $lines.Add("- Reboot if uptime is high and background services remain hot after closing apps.")
    $lines.Add("- Use `ACTP Performance Menu.bat` to view top CPU/RAM processes, clear temp files, and optionally close selected background apps.")
    $lines.Add("- Do not force-close editors, terminals, browser windows with unsaved work, sync tools, or install/update processes unless you intentionally want to stop them.")
    $lines.Add("- If Docker, Adobe, browser, game, or indexing processes dominate CPU/RAM, close them from their own UI first; use Task Manager or the provided PID-kill option only when they are stuck.")

    Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
}

New-DirectoryIfMissing -Path $OutputDir
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"

$baseline = Get-SystemSnapshot -SampleSeconds $SampleSeconds
$loadTest = $null
if (-not $SkipLoad) {
    $loadTest = Invoke-CpuLoadTest -Seconds $CpuSeconds -MemoryMB $MemoryMB
}
$afterLoad = Get-SystemSnapshot -SampleSeconds $SampleSeconds

$report = [pscustomobject]@{
    GeneratedAt = (Get-Date).ToString("s")
    Baseline = $baseline
    LoadTest = $loadTest
    AfterLoad = $afterLoad
}

$jsonPath = Join-Path $OutputDir "performance-report-$stamp.json"
$mdPath = Join-Path $OutputDir "performance-report-$stamp.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
Write-MarkdownReport -Report $report -Path $mdPath

Write-Output "REPORT_JSON=$jsonPath"
Write-Output "REPORT_MD=$mdPath"
Write-Output "BASELINE_CPU_LOAD=$($baseline.CpuLoadPercent)%"
Write-Output "BASELINE_FREE_RAM_GB=$($baseline.FreeRamGB)"
if ($loadTest) {
    Write-Output "LOAD_AVG_CPU=$($loadTest.AverageCpuLoadPercent)%"
    Write-Output "LOAD_PEAK_CPU=$($loadTest.PeakCpuLoadPercent)%"
    Write-Output "LOAD_MIN_FREE_RAM_GB=$($loadTest.MinimumFreeRamGB)"
}
Write-Output "AFTER_CPU_LOAD=$($afterLoad.CpuLoadPercent)%"
Write-Output "AFTER_FREE_RAM_GB=$($afterLoad.FreeRamGB)"
Write-Output "TOP_CPU_AFTER="
$afterLoad.TopCpuProcesses | Select-Object -First 10 | Format-Table CpuPercent,Id,ProcessName,WorkingSetMB -AutoSize
