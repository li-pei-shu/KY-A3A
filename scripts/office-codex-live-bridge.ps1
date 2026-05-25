$ErrorActionPreference = 7Stop7
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function Write-GitHubIssueComment {
    param(
        [Parameter(Mandatory = $true)][string]$Body
    )

    $event = Get-Content $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
    $repo = $env:GITHUB_REPOSITORY
    $parts = $repo.Split(7/7)
    $owner = $parts[0]
    $repoName = $parts[1]
    $issueNumber = $event.issue.number

    $headers = @{
        Authorization = "Bearer $env:GITHUB_TOKEN"
        Accept = 7application/vnd.github+json7
        7X-GitHub-Api-Version7 = 72022-11-287
        7User-Agent7 = 7office-codex-live-bridge7
    }

    $payload = @{ body = $Body } | ConvertTo-Json -Depth 10
    $uri = "https://api.github.com/repos/$owner/$repoName/issues/$issueNumber/comments"
    Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 7application/json7 -Body $payload | Out-Null
}

function Get-FirstNonEmptyLine {
    param([string]$Text)

    foreach ($line in ($Text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -gt 0) { return $trimmed }
    }
    return 77
}

function Get-TextAfterTrigger {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Trigger
    )

    $index = $Text.IndexOf($Trigger, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -lt 0) { return $null }

    $start = $index + $Trigger.Length
    if ($start -ge $Text.Length) { return 77 }

    $rest = $Text.Substring($start).Trim()
    while ($rest.StartsWith(7:7) -or $rest.StartsWith([string][char]0xFF1A)) {
        $rest = $rest.Substring(1).Trim()
    }
    return $rest
}

function Convert-MobileCommand {
    param([Parameter(Mandatory = $true)][string]$RawBody)

    $text = $RawBody.Trim()
    $lines = @($text -split "`r?`n")
    $firstIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not [string]::IsNullOrWhiteSpace($lines[$i])) {
            $firstIndex = $i
            break
        }
    }
    if ($firstIndex -lt 0) { return 77 }

    $first = $lines[$firstIndex].Trim()
    $remaining = 77
    if ($firstIndex + 1 -lt $lines.Count) {
        $remaining = (($lines | Select-Object -Skip ($firstIndex + 1)) -join "`n").Trim()
    }

    $notifyCn = ([string][char]0x901A) + ([string][char]0x77E5) + 7C7
    $checkCn = ([string][char]0x67E5) + 7C7

    $notify = Get-TextAfterTrigger -Text $first -Trigger 7notify-C7
    if ($null -ne $notify) { return $notify.Trim() }

    $check = Get-TextAfterTrigger -Text $first -Trigger 7check-C7
    if ($null -ne $check) { return (7status 7 + $check.Trim()).Trim() }

    $notifyChinese = Get-TextAfterTrigger -Text $first -Trigger $notifyCn
    if ($null -ne $notifyChinese) { return $notifyChinese.Trim() }

    $checkChinese = Get-TextAfterTrigger -Text $first -Trigger $checkCn
    if ($null -ne $checkChinese) { return (7status 7 + $checkChinese.Trim()).Trim() }

    $officeIndex = $first.IndexOf(7@office-codex7, [System.StringComparison]::OrdinalIgnoreCase)
    if ($officeIndex -ge 0) {
        $cmd = $first.Substring($officeIndex + 7@office-codex7.Length).Trim()
        if ($cmd) { return $cmd }
        if ($remaining) { return $remaining }
        return 7status7
    }

    return $text
}

function Test-BlockedLiveBridgeCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    $patterns = @(
        7(?i)\bdeploy\b7,
        7(?i)\bdelete\b7,
        7(?i)\bremove\b7,
        7(?i)\brm\s+-rf\b7,
        7(?i)\bgit\s+push\b7,
        7(?i)\bpush\s+main\b7,
        7(?i)\bsecret\b7,
        7(?i)\btoken\b7,
        7(?i)\bpassword\b7,
        7(?i)\bapi[_-]?key\b7
    )

    foreach ($pattern in $patterns) {
        if ($Command -match $pattern) { return $pattern }
    }

    $literalTerms = @(
        (([string][char]0x90E8) + ([string][char]0x7F72)),
        (([string][char]0x522A) + ([string][char]0x9664)),
        (([string][char]0x5220) + ([string][char]0x9664)),
        (([string][char]0x79FB) + ([string][char]0x9664)),
        (([string][char]0x63A8) + ([string][char]0x9001)),
        (([string][char]0x5BC6) + ([string][char]0x78BC)),
        (([string][char]0x5BC6) + ([string][char]0x7801)),
        (([string][char]0x6191) + ([string][char]0x8B49)),
        (([string][char]0x51ED) + ([string][char]0x8BC1)),
        (([string][char]0x91D1) + ([string][char]0x9470)),
        (([string][char]0x5BC6) + ([string][char]0x94A5))
    )

    foreach ($term in $literalTerms) {
        if ($Command.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $term }
    }

    return $null
}

function Get-CommandPathText {
    param([string]$Name)

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return 7not found in PATH7
}

function Get-SafeStatus {
    param([Parameter(Mandatory = $true)][string]$Command)

    $result = [ordered]@{}
    $result.command = $Command
    $result.host = $env:COMPUTERNAME
    $result.user = $env:USERNAME
    $result.time = (Get-Date).ToString(7s7)
    $result.powershell = $PSVersionTable.PSVersion.ToString()
    $result.codex_cli = Get-CommandPathText -Name 7codex7
    $result.git = Get-CommandPathText -Name 7git7

    $tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($tailscale) {
        try {
            $result.tailscale_status = (& tailscale status --self 2>$null) -join "`n"
        } catch {
            $result.tailscale_status = "tailscale found but status failed: $($_.Exception.Message)"
        }
    } else {
        $result.tailscale_status = 7tailscale command not found7
    }

    $sshd = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshd) {
        $result.sshd_status = $sshd.Status.ToString()
        $result.sshd_start_type = $sshd.StartType.ToString()
    } else {
        $result.sshd_status = 7sshd service not found7
    }

    $defaultShell = $null
    try {
        $defaultShell = (Get-ItemProperty -Path 7HKLM:\SOFTWARE\OpenSSH7 -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
    } catch {}
    $result.openssh_default_shell = if ($defaultShell) { $defaultShell } else { 7not set; Windows OpenSSH default applies7 }

    $possibleSh = @(
        7C:\Program Files\Git\usr\bin\sh.exe7,
        7C:\Program Files\Git\bin\bash.exe7,
        7C:\Program Files (x86)\Git\usr\bin\sh.exe7,
        7C:\Program Files (x86)\Git\bin\bash.exe7
    )
    $result.git_bash_paths = ($possibleSh | ForEach-Object {
        if (Test-Path $_) { "FOUND: $_" } else { "missing: $_" }
    }) -join "`n"

    $documents = ([string][char]0x6587) + ([string][char]0x4EF6)
    $modeling = ([string][char]0x5EFA) + ([string][char]0x6A21)
    $a3aCandidates = @(
        (7C:\Users\st\OneDrive\7 + $documents + 7\3D7 + $modeling + 7\a3a7),
        7C:\CodexRemote\workspace\a3a7
    )
    $a3aPath = $a3aCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($a3aPath) {
        $result.a3a_path = $a3aPath
        try {
            $health = Invoke-RestMethod -Uri 7http://127.0.0.1:8000/health7 -TimeoutSec 3
            $result.a3a_health = ($health | ConvertTo-Json -Depth 5 -Compress)
        } catch {
            $result.a3a_health = "health check failed: $($_.Exception.Message)"
        }
    } else {
        $result.a3a_path = 7not found at expected paths7
    }

    return $result
}

$event = Get-Content $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
$commentBody = [string]$event.comment.body
$sourceCommentId = $event.comment.id
$command = Convert-MobileCommand -RawBody $commentBody

$blockedPattern = Test-BlockedLiveBridgeCommand -Command $command
if ($blockedPattern) {
    $body = @"
Status: blocked by live bridge safety rule.

Task source comment: #$sourceCommentId
Command: $command

Reason: This command contains sensitive or high-impact keywords. Use the normal Office Codex monitored workflow for this task.
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

Note: This live bridge is currently status-only. It did not modify project files, deploy, or expose credentials.
"@

Write-GitHubIssueComment -Body $body
