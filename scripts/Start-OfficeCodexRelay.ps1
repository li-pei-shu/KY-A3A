param(
    [ValidateSet('start', 'stop', 'restart', 'status', 'logs', 'test-runner')]
    [string]$Action = 'status',

    [string]$Repo = $(if ($env:GITHUB_REPO) { $env:GITHUB_REPO } else { 'li-pei-shu/KY-A3A' }),
    [int]$Issue = $(if ($env:MOBILE_INBOX_ISSUE_NUMBER) { [int]$env:MOBILE_INBOX_ISSUE_NUMBER } else { 1 }),
    [string]$WorkDir = $(if ($env:OFFICE_CODEX_WORKDIR) { $env:OFFICE_CODEX_WORKDIR } else { 'C:\CodexRemote\workspace\KY-A3A' })
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$MonitorScript = Join-Path $WorkDir 'scripts\office-codex-issue-monitor.ps1'
$RunnerScript = Join-Path $WorkDir 'scripts\Invoke-OfficeCodexTask.ps1'
$LogDir = Join-Path $WorkDir 'logs'
$OutLog = Join-Path $LogDir 'office-codex-monitor.out.log'
$ErrLog = Join-Path $LogDir 'office-codex-monitor.err.log'

function Ensure-LogDir {
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir | Out-Null
    }
}

function Ensure-RelayEnv {
    [Environment]::SetEnvironmentVariable('GITHUB_REPO', $Repo, 'User')
    [Environment]::SetEnvironmentVariable('MOBILE_INBOX_ISSUE_NUMBER', [string]$Issue, 'User')
    [Environment]::SetEnvironmentVariable('OFFICE_CODEX_WORKDIR', $WorkDir, 'User')

    $env:GITHUB_REPO = $Repo
    $env:MOBILE_INBOX_ISSUE_NUMBER = [string]$Issue
    $env:OFFICE_CODEX_WORKDIR = $WorkDir

    $token = [Environment]::GetEnvironmentVariable('GITHUB_TOKEN', 'Process')
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = [Environment]::GetEnvironmentVariable('GITHUB_TOKEN', 'User')
    }

    if ([string]::IsNullOrWhiteSpace($token) -and ($Action -in @('start', 'restart'))) {
        Write-Host 'Paste GitHub token. Input will be hidden:'
        $secure = Read-Host -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
        [Environment]::SetEnvironmentVariable('GITHUB_TOKEN', $token, 'User')
    }

    if (-not [string]::IsNullOrWhiteSpace($token)) {
        $env:GITHUB_TOKEN = $token
    }
}

function Get-MonitorProcesses {
    Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -like '*office-codex-issue-monitor.ps1*'
    }
}

function Stop-Monitor {
    $items = @(Get-MonitorProcesses)
    if ($items.Count -eq 0) {
        Write-Host 'No monitor process found.'
        return
    }

    foreach ($p in $items) {
        Write-Host ('Stopping monitor PID ' + $p.ProcessId)
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Start-Monitor {
    Ensure-RelayEnv
    Ensure-LogDir

    if (-not (Test-Path $MonitorScript)) {
        throw "Monitor script not found: $MonitorScript"
    }

    Remove-Item $OutLog -ErrorAction SilentlyContinue
    Remove-Item $ErrLog -ErrorAction SilentlyContinue

    Start-Process powershell `
        -WorkingDirectory $WorkDir `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $MonitorScript `
        -RedirectStandardOutput $OutLog `
        -RedirectStandardError $ErrLog `
        -WindowStyle Hidden

    Start-Sleep -Seconds 3
    Show-Status
}

function Show-Status {
    Ensure-RelayEnv
    $items = @(Get-MonitorProcesses)

    Write-Host ('Repo=' + $Repo)
    Write-Host ('Issue=' + $Issue)
    Write-Host ('WorkDir=' + $WorkDir)
    if ($env:GITHUB_TOKEN) {
        Write-Host ('GITHUB_TOKEN=SET length=' + $env:GITHUB_TOKEN.Length)
    } else {
        Write-Host 'GITHUB_TOKEN=EMPTY'
    }

    Write-Host ('MONITOR_COUNT=' + $items.Count)
    if ($items.Count -gt 0) {
        $items | Select-Object ProcessId, CommandLine | Format-List
    }

    Write-Host '---- ERR LOG ----'
    if (Test-Path $ErrLog) {
        Get-Content $ErrLog -Tail 40
    } else {
        Write-Host 'NO_ERR_LOG'
    }

    Write-Host '---- OUT LOG ----'
    if (Test-Path $OutLog) {
        Get-Content $OutLog -Tail 40
    } else {
        Write-Host 'NO_OUT_LOG'
    }
}

function Show-Logs {
    Write-Host '---- ERR LOG ----'
    if (Test-Path $ErrLog) { Get-Content $ErrLog -Tail 120 } else { Write-Host 'NO_ERR_LOG' }
    Write-Host '---- OUT LOG ----'
    if (Test-Path $OutLog) { Get-Content $OutLog -Tail 120 } else { Write-Host 'NO_OUT_LOG' }
}

function Test-Runner {
    Ensure-RelayEnv
    if (-not (Test-Path $RunnerScript)) {
        throw "Runner script not found: $RunnerScript"
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $RunnerScript -TaskBody 'Reply exactly OFFICE_CODEX_LOCAL_ALIVE. Do not modify files.' -CommentId 'local-direct-test'
}

switch ($Action) {
    'start' { Start-Monitor }
    'stop' { Stop-Monitor }
    'restart' { Stop-Monitor; Start-Sleep -Seconds 2; Start-Monitor }
    'status' { Show-Status }
    'logs' { Show-Logs }
    'test-runner' { Test-Runner }
}
