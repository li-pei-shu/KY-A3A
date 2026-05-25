$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()
$NewLine = [Environment]::NewLine

function Write-GitHubIssueComment {
    param([Parameter(Mandatory = $true)][string]$Body)

    $event = Get-Content $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
    $parts = $env:GITHUB_REPOSITORY.Split('/')
    $uri = 'https://api.github.com/repos/' + $parts[0] + '/' + $parts[1] + '/issues/' + $event.issue.number + '/comments'
    $headers = @{
        Authorization = 'Bearer ' + $env:GITHUB_TOKEN
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'office-codex-live-bridge'
    }
    $payload = @{ body = $Body } | ConvertTo-Json -Depth 10
    $payloadBytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $payloadBytes | Out-Null
}

function Get-TextAfterTrigger {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Trigger
    )

    $index = $Text.IndexOf($Trigger, [System.StringComparison]::OrdinalIgnoreCase)
    if ($index -lt 0) { return $null }
    $start = $index + $Trigger.Length
    if ($start -ge $Text.Length) { return '' }

    $rest = $Text.Substring($start).Trim()
    while ($rest.StartsWith(':') -or $rest.StartsWith([string][char]0xFF1A)) {
        $rest = $rest.Substring(1).Trim()
    }
    return $rest
}

function Convert-MobileCommand {
    param([Parameter(Mandatory = $true)][string]$RawBody)

    $text = $RawBody.Trim()
    $lines = @($text.Replace([string][char]13, '') -split ([string][char]10))
    $firstIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not [string]::IsNullOrWhiteSpace($lines[$i])) {
            $firstIndex = $i
            break
        }
    }
    if ($firstIndex -lt 0) { return '' }

    $first = $lines[$firstIndex].Trim()
    $remaining = ''
    if ($firstIndex + 1 -lt $lines.Count) {
        $remaining = (($lines | Select-Object -Skip ($firstIndex + 1)) -join ([string][char]10)).Trim()
    }

    $notifyCn = ([string][char]0x901A) + ([string][char]0x77E5) + 'C'
    $checkCn = ([string][char]0x67E5) + 'C'

    $notify = Get-TextAfterTrigger -Text $first -Trigger 'notify-C'
    if ($null -ne $notify) { return $notify.Trim() }

    $check = Get-TextAfterTrigger -Text $first -Trigger 'check-C'
    if ($null -ne $check) { return ('status ' + $check.Trim()).Trim() }

    $notifyChinese = Get-TextAfterTrigger -Text $first -Trigger $notifyCn
    if ($null -ne $notifyChinese) { return $notifyChinese.Trim() }

    $checkChinese = Get-TextAfterTrigger -Text $first -Trigger $checkCn
    if ($null -ne $checkChinese) { return ('status ' + $checkChinese.Trim()).Trim() }

    $officeIndex = $first.IndexOf('@office-codex', [System.StringComparison]::OrdinalIgnoreCase)
    if ($officeIndex -ge 0) {
        $cmd = $first.Substring($officeIndex + '@office-codex'.Length).Trim()
        if ($cmd) { return $cmd }
        if ($remaining) { return $remaining }
        return 'status'
    }

    return $text
}

function Test-BlockedLiveBridgeCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    $lower = $Command.ToLowerInvariant()
    $asciiTerms = @(
        'deploy',
        'delete',
        'remove',
        'rm -rf',
        'git push',
        'push main',
        'secret',
        'token',
        'password',
        'api_key',
        'api-key',
        'api key'
    )
    foreach ($term in $asciiTerms) {
        if ($lower.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $term }
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
    return 'not found in PATH'
}

function Get-SafeStatus {
    param([Parameter(Mandatory = $true)][string]$Command)

    $result = [ordered]@{}
    $result.command = $Command
    $result.host = $env:COMPUTERNAME
    $result.user = $env:USERNAME
    $result.time = (Get-Date).ToString('s')
    $result.powershell = $PSVersionTable.PSVersion.ToString()
    $result.codex_cli = Get-CommandPathText -Name 'codex'
    $result.git = Get-CommandPathText -Name 'git'

    $tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
    if ($tailscale) {
        try {
            $result.tailscale_status = (& tailscale status --self 2>$null) -join ([string][char]10)
        } catch {
            $result.tailscale_status = 'tailscale found but status failed: ' + $_.Exception.Message
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
        $defaultShell = (Get-ItemProperty -Path 'HKLM:/SOFTWARE/OpenSSH' -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
    } catch {}
    $result.openssh_default_shell = if ($defaultShell) { $defaultShell } else { 'not set; Windows OpenSSH default applies' }

    $possibleSh = @(
        'C:/Program Files/Git/usr/bin/sh.exe',
        'C:/Program Files/Git/bin/bash.exe',
        'C:/Program Files (x86)/Git/usr/bin/sh.exe',
        'C:/Program Files (x86)/Git/bin/bash.exe'
    )
    $result.git_bash_paths = ($possibleSh | ForEach-Object {
        if (Test-Path $_) { 'FOUND: ' + $_ } else { 'missing: ' + $_ }
    }) -join ([string][char]10)

    $documents = ([string][char]0x6587) + ([string][char]0x4EF6)
    $modeling = ([string][char]0x5EFA) + ([string][char]0x6A21)
    $a3aCandidates = @(
        ('C:/Users/st/OneDrive/' + $documents + '/3D' + $modeling + '/a3a'),
        'C:/CodexRemote/workspace/a3a'
    )
    $a3aPath = $a3aCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($a3aPath) {
        $result.a3a_path = $a3aPath
        try {
            $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 3
            $result.a3a_health = ($health | ConvertTo-Json -Depth 5 -Compress)
        } catch {
            $result.a3a_health = 'health check failed: ' + $_.Exception.Message
        }
    } else {
        $result.a3a_path = 'not found at expected paths'
    }

    return $result
}

function Test-StatusOnlyCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    $trimmed = $Command.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $true }
    if ($trimmed.StartsWith('status', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($trimmed.StartsWith('check', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}

function Resolve-OfficeCodexWorkDir {
    param([Parameter(Mandatory = $true)][string]$Command)

    $bridgeRepo = 'C:/Users/st/Documents/Codex/2026-05-22/gpt-codex-codex/KY-A3A'
    $documents = ([string][char]0x6587) + ([string][char]0x4EF6)
    $modeling = ([string][char]0x5EFA) + ([string][char]0x6A21)
    $a3aRepo = 'C:/Users/st/OneDrive/' + $documents + '/3D' + $modeling + '/a3a'

    $lower = $Command.ToLowerInvariant()
    $mentionsBridge = (
        $lower.Contains('ky-a3a') -or
        $lower.Contains('github') -or
        $lower.Contains('issue') -or
        $lower.Contains('relay') -or
        $lower.Contains('runner')
    )
    if ($mentionsBridge -and (Test-Path -LiteralPath $bridgeRepo)) { return (Resolve-Path $bridgeRepo).Path }

    $mentionsA3a = (
        $lower.Contains('3d') -or
        $lower.Contains('a3a') -or
        $Command.Contains($modeling)
    )
    if ($mentionsA3a -and (Test-Path -LiteralPath $a3aRepo)) { return (Resolve-Path $a3aRepo).Path }

    if ($env:OFFICE_CODEX_WORKDIR -and (Test-Path -LiteralPath $env:OFFICE_CODEX_WORKDIR)) {
        return (Resolve-Path $env:OFFICE_CODEX_WORKDIR).Path
    }

    if (Test-Path -LiteralPath $bridgeRepo) { return (Resolve-Path $bridgeRepo).Path }
    return (Get-Location).Path
}

function Get-SafeCommentText {
    param(
        [string]$Text,
        [int]$MaxChars = 5000
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $safe = $Text
    $redactions = @(
        '(?i)(github[_-]?token\s*[=:]\s*)\S+',
        '(?i)(openai[_-]?api[_-]?key\s*[=:]\s*)\S+',
        '(?i)(api[_-]?key\s*[=:]\s*)\S+',
        '(?i)(password\s*[=:]\s*)\S+',
        '(?i)(secret\s*[=:]\s*)\S+',
        '(?i)(token\s*[=:]\s*)\S+',
        'gh[pousr]_[A-Za-z0-9_]+',
        'sk-[A-Za-z0-9_-]+'
    )
    foreach ($pattern in $redactions) {
        $safe = [regex]::Replace($safe, $pattern, '$1[REDACTED]')
    }
    if ($safe.Length -gt $MaxChars) {
        $safe = $safe.Substring(0, $MaxChars) + "`n...[truncated]"
    }
    return $safe.Trim()
}

function Invoke-OfficeCodexTaskRunner {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$CommentId,
        [Parameter(Mandatory = $true)][string]$WorkDir
    )

    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
    $runnerScript = Join-Path $scriptDir 'Invoke-OfficeCodexTask.ps1'
    if (-not (Test-Path -LiteralPath $runnerScript)) {
        throw "Runner script not found: $runnerScript"
    }

    $jsonText = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runnerScript -TaskBody $Command -CommentId $CommentId -WorkDir $WorkDir
    if ($LASTEXITCODE -ne 0) {
        throw "Runner process failed with exit code $LASTEXITCODE."
    }

    try {
        return ($jsonText | ConvertFrom-Json)
    } catch {
        $safe = Get-SafeCommentText -Text (($jsonText | Out-String).Trim()) -MaxChars 3000
        return [pscustomobject]@{
            status = 'failed'
            comment_id = $CommentId
            exit_code = -1
            reason = 'Runner returned non-JSON output.'
            summary = ''
            output_tail = $safe
            workdir = $WorkDir
            changed_files = 'unknown'
            deployment = 'none'
        }
    }
}

function Convert-TaskResultToIssueBody {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$CommentId,
        [Parameter(Mandatory = $true)][string]$Command
    )

    $status = if ($Result.status) { [string]$Result.status } else { 'failed' }
    $exitCode = if ($null -ne $Result.exit_code) { [string]$Result.exit_code } else { 'unknown' }
    $reason = Get-SafeCommentText -Text ([string]$Result.reason) -MaxChars 1200
    $summary = Get-SafeCommentText -Text ([string]$Result.summary) -MaxChars 5000
    $outputTail = Get-SafeCommentText -Text ([string]$Result.output_tail) -MaxChars 3500
    $workdir = Get-SafeCommentText -Text ([string]$Result.workdir) -MaxChars 500
    $changedFiles = Get-SafeCommentText -Text ([string]$Result.changed_files) -MaxChars 1600
    $deployment = if ($Result.deployment) { Get-SafeCommentText -Text ([string]$Result.deployment) -MaxChars 500 } else { 'none' }
    $needDecision = if ($status -eq 'blocked') { 'yes' } else { 'no' }

    $parts = @(
        "Status: $status by Office Codex task runner.",
        '',
        "Task source comment: #$CommentId",
        "Command: $Command",
        "Workdir: $workdir",
        "Exit code: $exitCode",
        "Need user decision: $needDecision",
        "Files changed: $(if ($changedFiles) { $changedFiles } else { 'none' })",
        "Deployment: $deployment"
    )

    if ($reason) {
        $parts += @('', 'Reason: ' + $reason)
    }
    if ($summary) {
        $parts += @('', 'Summary:', '```text', $summary, '```')
    }
    if ($outputTail) {
        $parts += @('', 'Output tail:', '```text', $outputTail, '```')
    }

    return ($parts -join $NewLine)
}

$event = Get-Content $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
$commentBody = [string]$event.comment.body
$sourceCommentId = ([System.Convert]::ToString($event.comment.id, [System.Globalization.CultureInfo]::InvariantCulture) -replace '[^\d]', '')
$command = Convert-MobileCommand -RawBody $commentBody

$blockedPattern = Test-BlockedLiveBridgeCommand -Command $command
if ($blockedPattern) {
    $body = @(
        'Status: blocked by live bridge safety rule.',
        '',
        "Task source comment: #$sourceCommentId",
        'Command: ' + $command,
        '',
        'Reason: This command contains sensitive or high-impact keywords. Use the normal Office Codex monitored workflow for this task.'
    ) -join $NewLine
    Write-GitHubIssueComment -Body $body
    exit 0
}

if (Test-StatusOnlyCommand -Command $command) {
    $status = Get-SafeStatus -Command $command
    $statusText = ($status.GetEnumerator() | ForEach-Object {
        '## ' + $_.Key + $NewLine + $_.Value
    }) -join ($NewLine + $NewLine)

    $body = @(
        'Status: live bridge checked on codexwindows.',
        '',
        "Task source comment: #$sourceCommentId",
        '',
        $statusText,
        '',
        'Note: This status check did not modify project files, deploy, or expose credentials.'
    ) -join $NewLine

    Write-GitHubIssueComment -Body $body
    exit 0
}

try {
    $workDir = Resolve-OfficeCodexWorkDir -Command $command
    $result = Invoke-OfficeCodexTaskRunner -Command $command -CommentId $sourceCommentId -WorkDir $workDir
    $body = Convert-TaskResultToIssueBody -Result $result -CommentId $sourceCommentId -Command $command
    Write-GitHubIssueComment -Body $body
} catch {
    $body = @(
        'Status: failed by Office Codex task runner.',
        '',
        "Task source comment: #$sourceCommentId",
        "Command: $command",
        'Exit code: -1',
        'Need user decision: yes',
        'Files changed: unknown',
        'Deployment: none',
        '',
        'Reason: ' + (Get-SafeCommentText -Text $_.Exception.Message -MaxChars 1200)
    ) -join $NewLine
    Write-GitHubIssueComment -Body $body
}
