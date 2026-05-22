$ErrorActionPreference = 'Stop'

<#
Office Codex Issue Monitor

Purpose:
- Poll GitHub Issue #1 in li-pei-shu/KY-A3A.
- Find new commands that contain @office-codex, 通知C, or 查C.
- Immediately reply with "Status: received by Office Codex".
- For safe status commands, reply with a status report.
- Store processed comment ids locally to avoid duplicate replies.

Required environment variable:
- GITHUB_TOKEN or OFFICE_CODEX_GITHUB_TOKEN

Token scope:
- Fine-grained token with access to li-pei-shu/KY-A3A issues: read/write.

Safety:
- Does not modify project files.
- Does not deploy.
- Does not reveal credentials.
#>

$Owner = 'li-pei-shu'
$Repo = 'KY-A3A'
$IssueNumber = 1
$PollSeconds = 60
$StateDir = Join-Path $env:USERPROFILE '.office-codex-relay'
$StateFile = Join-Path $StateDir 'processed-comments.json'

if (-not (Test-Path $StateDir)) {
    New-Item -ItemType Directory -Path $StateDir | Out-Null
}

function Get-Token {
    if ($env:OFFICE_CODEX_GITHUB_TOKEN) { return $env:OFFICE_CODEX_GITHUB_TOKEN }
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    throw 'Missing OFFICE_CODEX_GITHUB_TOKEN or GITHUB_TOKEN environment variable.'
}

function Get-Headers {
    $token = Get-Token
    return @{
        Authorization = "Bearer $token"
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'office-codex-issue-monitor'
    }
}

function Invoke-GitHubGet {
    param([string]$Uri)
    Invoke-RestMethod -Method Get -Uri $Uri -Headers (Get-Headers)
}

function Add-IssueComment {
    param([string]$Body)
    $uri = "https://api.github.com/repos/$Owner/$Repo/issues/$IssueNumber/comments"
    $payload = @{ body = $Body } | ConvertTo-Json -Depth 20
    Invoke-RestMethod -Method Post -Uri $uri -Headers (Get-Headers) -ContentType 'application/json' -Body $payload | Out-Null
}

function Load-ProcessedIds {
    if (-not (Test-Path $StateFile)) { return @{} }
    try {
        $json = Get-Content $StateFile -Raw | ConvertFrom-Json
        $map = @{}
        foreach ($p in $json.PSObject.Properties) { $map[$p.Name] = $true }
        return $map
    } catch {
        return @{}
    }
}

function Save-ProcessedIds {
    param([hashtable]$Map)
    $obj = [ordered]@{}
    foreach ($key in $Map.Keys) { $obj[$key] = $true }
    ($obj | ConvertTo-Json -Depth 10) | Set-Content -Path $StateFile -Encoding UTF8
}

function Is-OfficeCodexCommand {
    param([string]$Body)
    if ($Body -match '@office-codex') { return $true }
    if ($Body -match '通知C[:：]') { return $true }
    if ($Body -match '查C[:：]') { return $true }
    return $false
}

function Convert-Command {
    param([string]$Body)
    $text = $Body.Trim()
    if ($text -match '通知C[:：]\s*(.+)') { return $Matches[1].Trim() }
    if ($text -match '查C[:：]\s*(.+)') { return ('status ' + $Matches[1].Trim()) }
    if ($text -match '@office-codex\s*(.*)') {
        $cmd = $Matches[1].Trim()
        if ($cmd) { return $cmd }
        return 'status'
    }
    return $text
}

function Test-UnsafeCommand {
    param([string]$Command)
    $unsafe = @('password','token','secret','key','密碼','憑證','刪除','delete','部署','deploy','付費','付款','runner registration token')
    foreach ($u in $unsafe) {
        if ($Command -match [regex]::Escape($u)) { return $true }
    }
    return $false
}

function Get-RunnerLocalStatus {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Host: $env:COMPUTERNAME")
    $lines.Add("User: $env:USERNAME")
    $lines.Add("Time: $((Get-Date).ToString('s'))")

    # Check common GitHub runner folders without exposing secrets.
    $candidateDirs = @(
        (Join-Path $env:USERPROFILE 'actions-runner'),
        'C:\actions-runner',
        'C:\GitHubActionsRunner',
        (Join-Path $env:USERPROFILE 'Downloads\actions-runner')
    )

    $foundRunner = $false
    foreach ($dir in $candidateDirs) {
        if (Test-Path $dir) {
            $foundRunner = $true
            $lines.Add("Runner folder found: $dir")
            if (Test-Path (Join-Path $dir '.runner')) { $lines.Add('Runner config file: found') }
            if (Test-Path (Join-Path $dir 'run.cmd')) { $lines.Add('run.cmd: found') }
            if (Test-Path (Join-Path $dir 'svc.sh')) { $lines.Add('svc.sh: found') }
        }
    }
    if (-not $foundRunner) { $lines.Add('Runner folder: not found in common paths') }

    $services = Get-Service | Where-Object { $_.Name -like 'actions.runner.*' -or $_.DisplayName -like '*GitHub Actions Runner*' }
    if ($services) {
        foreach ($svc in $services) { $lines.Add("Runner service: $($svc.Name) / $($svc.Status)") }
    } else {
        $lines.Add('Runner service: not found')
    }

    return ($lines -join "`n")
}

function Get-SafeStatusReport {
    param([string]$Command)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Command: $Command")
    $lines.Add("Host: $env:COMPUTERNAME")
    $lines.Add("User: $env:USERNAME")
    $lines.Add("Time: $((Get-Date).ToString('s'))")

    if ($Command -match 'runner') {
        $lines.Add('')
        $lines.Add('Runner status:')
        $lines.Add((Get-RunnerLocalStatus))
    }

    if ($Command -match 'ssh|SSH|sh|Git Bash|bash') {
        $sshd = Get-Service sshd -ErrorAction SilentlyContinue
        if ($sshd) { $lines.Add("sshd: $($sshd.Status) / $($sshd.StartType)") } else { $lines.Add('sshd: not found') }

        $defaultShell = $null
        try { $defaultShell = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell } catch {}
        if ($defaultShell) { $lines.Add("OpenSSH DefaultShell: $defaultShell") } else { $lines.Add('OpenSSH DefaultShell: not set') }

        $shPaths = @('C:\Program Files\Git\usr\bin\sh.exe','C:\Program Files\Git\bin\bash.exe')
        foreach ($p in $shPaths) {
            if (Test-Path $p) { $lines.Add("Found: $p") } else { $lines.Add("Missing: $p") }
        }
    }

    if ($Command -match '3D|A3A|建模|status') {
        $a3a = 'C:\Users\st\OneDrive\文件\3D建模\a3a'
        if (Test-Path $a3a) { $lines.Add("A3A path: $a3a") } else { $lines.Add('A3A path: not found at expected path') }
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 3
            $lines.Add('A3A health: ' + (($health | ConvertTo-Json -Compress -Depth 10)))
        } catch { $lines.Add('A3A health: failed - ' + $_.Exception.Message) }
    }

    return ($lines -join "`n")
}

function Process-Comment {
    param($Comment)

    $commentId = [string]$Comment.id
    $body = [string]$Comment.body
    $command = Convert-Command -Body $body

    $ack = @"
Status: received by Office Codex.
Task source comment: #$commentId
Command: $command
"@
    Add-IssueComment -Body $ack

    if (Test-UnsafeCommand -Command $command) {
        $blocked = @"
Status: blocked.
Task source comment: #$commentId
Command: $command
Reason: command contains sensitive or high-impact terms. Please confirm explicitly before execution.
Need user decision: yes
"@
        Add-IssueComment -Body $blocked
        return
    }

    $report = Get-SafeStatusReport -Command $command
    $result = @"
Status: done.
Task source comment: #$commentId

$result

Need user decision: no, unless you want follow-up action.
"@
    Add-IssueComment -Body $result
}

Write-Host 'Office Codex Issue Monitor started.'
Write-Host "Repo: $Owner/$Repo Issue #$IssueNumber Poll: $PollSeconds sec"

while ($true) {
    try {
        $processed = Load-ProcessedIds
        $uri = "https://api.github.com/repos/$Owner/$Repo/issues/$IssueNumber/comments?per_page=100"
        $comments = Invoke-GitHubGet -Uri $uri

        foreach ($comment in $comments) {
            $id = [string]$comment.id
            if ($processed.ContainsKey($id)) { continue }
            $authorType = [string]$comment.user.type
            $body = [string]$comment.body
            if ($authorType -eq 'Bot') {
                $processed[$id] = $true
                continue
            }
            if (Is-OfficeCodexCommand -Body $body) {
                Process-Comment -Comment $comment
            }
            $processed[$id] = $true
        }
        Save-ProcessedIds -Map $processed
    } catch {
        Write-Host ('Monitor error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSeconds
}
