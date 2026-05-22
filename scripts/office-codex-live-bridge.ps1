$ErrorActionPreference = 'Stop'

function Write-GitHubIssueComment {
    param(
        [Parameter(Mandatory = $true)][string]$Body
    )

    $event = Get-Content $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
    $repo = $env:GITHUB_REPOSITORY
    $parts = $repo.Split('/')
    $owner = $parts[0]
    $repoName = $parts[1]
    $issueNumber = $event.issue.number

    $headers = @{
        Authorization = "Bearer $env:GITHUB_TOKEN"
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    $payload = @{ body = $Body } | ConvertTo-Json -Depth 10
    $uri = "https://api.github.com/repos/$owner/$repoName/issues/$issueNumber/comments"
    Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json' -Body $payload | Out-Null
}

function Convert-MobileCommand {
    param([Parameter(Mandatory = $true)][string]$RawBody)

    $text = $RawBody.Trim()

    if ($text -match '通知C[:：]\s*(.+)') {
        return $Matches[1].Trim()
    }

    if ($text -match '查C[:：]\s*(.+)') {
        return ('status ' + $Matches[1].Trim())
    }

    if ($text -match '@office-codex\s*(.*)') {
        $cmd = $Matches[1].Trim()
        if ($cmd.Length -gt 0) { return $cmd }
    }

    return $text
}

function Get-SafeStatus {
    param([Parameter(Mandatory = $true)][string]$Command)

    $result = [ordered]@{}
    $result.command = $Command
    $result.host = $env:COMPUTERNAME
    $result.user = $env:USERNAME
    $result.time = (Get-Date).ToString('s')

    $tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($tailscale) {
        try {
            $result.tailscale_status = (& tailscale status --self 2>$null) -join "`n"
        } catch {
            $result.tailscale_status = "tailscale found but status failed: $($_.Exception.Message)"
        }
    } else {
        $result.tailscale_status = 'tailscale command not found'
    }

    $sshd = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshd) {
        $result.sshd_status = $sshd.Status.ToString()
        $result.sshd_start_type = $sshd.StartType.ToString()
    } else {
        $result.sshd_status = 'sshd service not found'
    }

    $defaultShell = $null
    try {
        $defaultShell = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
    } catch {}
    $result.openssh_default_shell = if ($defaultShell) { $defaultShell } else { 'not set; Windows OpenSSH default applies' }

    $possibleSh = @(
        'C:\Program Files\Git\usr\bin\sh.exe',
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\usr\bin\sh.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    )
    $result.git_bash_paths = ($possibleSh | ForEach-Object {
        if (Test-Path $_) { "FOUND: $_" } else { "missing: $_" }
    }) -join "`n"

    $a3aPath = 'C:\Users\st\OneDrive\文件\3D建模\a3a'
    if (Test-Path $a3aPath) {
        $result.a3a_path = $a3aPath
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 3
            $result.a3a_health = ($health | ConvertTo-Json -Depth 5 -Compress)
        } catch {
            $result.a3a_health = "health check failed: $($_.Exception.Message)"
        }
    } else {
        $result.a3a_path = 'not found at expected path'
    }

    return $result
}

$event = Get-Content $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
$commentBody = [string]$event.comment.body
$sourceCommentId = $event.comment.id
$command = Convert-MobileCommand -RawBody $commentBody

# Avoid dangerous operations in this live bridge. It reports status only.
$blockedKeywords = @('密碼', 'password', 'token', 'secret', '刪除', 'delete', '部署', 'deploy', '付款', '付費')
$blocked = $false
foreach ($kw in $blockedKeywords) {
    if ($command -match [regex]::Escape($kw)) { $blocked = $true }
}

if ($blocked) {
    $body = @"
Status: blocked by live bridge safety rule.

Task source comment: #$sourceCommentId
Command: $command

Reason: This command contains sensitive or high-impact keywords. Office Codex should handle it through the normal monitored workflow with explicit confirmation.
"@
    Write-GitHubIssueComment -Body $body
    exit 0
}

$status = Get-SafeStatus -Command $command
$statusText = ($status.GetEnumerator() | ForEach-Object {
    "## $($_.Key)`n$($_.Value)"
}) -join "`n`n"

$body = @"
Status: live bridge checked on codexwindows.

Task source comment: #$sourceCommentId

$statusText

Note: This live bridge is currently status-only. It did not modify project files, deploy, or expose any credentials.
"@

Write-GitHubIssueComment -Body $body
