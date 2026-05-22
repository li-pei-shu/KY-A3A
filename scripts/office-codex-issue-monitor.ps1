$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

<#
Office Codex Issue Monitor

Purpose:
- Poll GitHub Issue #1 in li-pei-shu/KY-A3A.
- Find new commands that contain @office-codex, notify-C, check-C, or the Chinese aliases.
- Immediately reply with "Status: received task <comment id>".
- Call scripts/Invoke-OfficeCodexTask.ps1 for safe tasks.
- Reply with the runner result.
- Store processed comment ids locally to avoid duplicate execution.

Required environment variable:
- GITHUB_TOKEN

Optional environment variables:
- GITHUB_REPO=li-pei-shu/KY-A3A
- MOBILE_INBOX_ISSUE_NUMBER=1
- OFFICE_CODEX_WORKDIR=<local repo path>

Safety:
- Does not write tokens to disk.
- Does not auto-push main.
- Does not deploy.
- Dangerous tasks are blocked by Invoke-OfficeCodexTask.ps1 and require manual confirmation.
#>

$GitHubRepo = if ($env:GITHUB_REPO) { $env:GITHUB_REPO } else { 'li-pei-shu/KY-A3A' }
$RepoParts = $GitHubRepo.Split('/', 2)
if ($RepoParts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($RepoParts[0]) -or [string]::IsNullOrWhiteSpace($RepoParts[1])) {
    throw "Invalid GITHUB_REPO value '$GitHubRepo'. Expected owner/repo."
}

$Owner = $RepoParts[0]
$Repo = $RepoParts[1]
$IssueNumber = if ($env:MOBILE_INBOX_ISSUE_NUMBER) { [int]$env:MOBILE_INBOX_ISSUE_NUMBER } else { 1 }
$PollSeconds = 60
$StateDir = Join-Path $env:USERPROFILE '.office-codex-relay'
$StateFile = Join-Path $StateDir 'processed-comments.json'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunnerScript = Join-Path $ScriptDir 'Invoke-OfficeCodexTask.ps1'

# Build Chinese trigger strings from Unicode code points to avoid PowerShell 5.1 source-encoding issues.
$NotifyTrigger = ([string][char]0x901A) + ([string][char]0x77E5) + 'C'
$CheckTrigger = ([string][char]0x67E5) + 'C'

if (-not (Test-Path $StateDir)) {
    New-Item -ItemType Directory -Path $StateDir | Out-Null
}

function Get-Token {
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    throw 'Missing GITHUB_TOKEN environment variable.'
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

function Is-OfficeCodexCommand {
    param([string]$Body)
    if ($Body.IndexOf('@office-codex', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    if ($Body.IndexOf('notify-C', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    if ($Body.IndexOf('check-C', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    if ($Body.IndexOf($script:NotifyTrigger, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    if ($Body.IndexOf($script:CheckTrigger, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    return $false
}

function Convert-Command {
    param([string]$Body)
    $text = $Body.Trim()

    $notify = Get-TextAfterTrigger -Text $text -Trigger 'notify-C'
    if ($null -ne $notify) { return $notify.Trim() }

    $check = Get-TextAfterTrigger -Text $text -Trigger 'check-C'
    if ($null -ne $check) { return ('status ' + $check.Trim()).Trim() }

    $notifyCn = Get-TextAfterTrigger -Text $text -Trigger $script:NotifyTrigger
    if ($null -ne $notifyCn) { return $notifyCn.Trim() }

    $checkCn = Get-TextAfterTrigger -Text $text -Trigger $script:CheckTrigger
    if ($null -ne $checkCn) { return ('status ' + $checkCn.Trim()).Trim() }

    $officeIndex = $text.IndexOf('@office-codex', [System.StringComparison]::OrdinalIgnoreCase)
    if ($officeIndex -ge 0) {
        $cmd = $text.Substring($officeIndex + '@office-codex'.Length).Trim()
        if ($cmd) { return $cmd }
        return 'status'
    }

    return $text
}

function Convert-RunnerResultToIssueBody {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$CommentId,
        [Parameter(Mandatory = $true)][string]$Command
    )

    $status = if ($Result.status) { [string]$Result.status } else { 'failed' }
    $exitCode = if ($null -ne $Result.exit_code) { [string]$Result.exit_code } else { 'unknown' }
    $reason = if ($Result.reason) { [string]$Result.reason } else { '' }
    $summary = if ($Result.summary) { [string]$Result.summary } else { '' }
    $outputTail = if ($Result.output_tail) { [string]$Result.output_tail } else { '' }
    $needDecision = if ($status -eq 'blocked') { 'yes' } else { 'no' }

    if ($outputTail.Length -gt 6000) {
        $outputTail = $outputTail.Substring($outputTail.Length - 6000)
    }

    $body = @"
Status: $status.
Task source comment: #$CommentId
Command: $Command
Exit code: $exitCode
Need user decision: $needDecision
"@

    if ($reason) { $body += "`nReason: $reason`n" }
    if ($summary) { $body += "`nSummary: $summary`n" }
    if ($outputTail) {
        $body += @"

Output tail:
``````text
$outputTail
``````
"@
    }

    return $body
}

function Invoke-OfficeCodexRunner {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$CommentId
    )

    if (-not (Test-Path $RunnerScript)) {
        throw "Runner script not found: $RunnerScript"
    }

    $jsonText = & powershell -NoProfile -ExecutionPolicy Bypass -File $RunnerScript -TaskBody $Command -CommentId $CommentId
    if ($LASTEXITCODE -ne 0) {
        throw "Runner process failed with exit code $LASTEXITCODE."
    }

    try {
        return ($jsonText | ConvertFrom-Json)
    } catch {
        $safe = ($jsonText | Out-String).Trim()
        return [pscustomobject]@{
            status = 'failed'
            comment_id = $CommentId
            exit_code = -1
            reason = 'Runner returned non-JSON output.'
            summary = ''
            output_tail = $safe
        }
    }
}

function Process-Comment {
    param($Comment)

    $commentId = [string]$Comment.id
    $body = [string]$Comment.body
    $command = Convert-Command -Body $body

    $ack = @"
Status: received task $commentId.
Task source comment: #$commentId
Command: $command
"@
    Add-IssueComment -Body $ack

    try {
        $result = Invoke-OfficeCodexRunner -Command $command -CommentId $commentId
        $reply = Convert-RunnerResultToIssueBody -Result $result -CommentId $commentId -Command $command
        Add-IssueComment -Body $reply
    } catch {
        $failed = @"
Status: failed.
Task source comment: #$commentId
Command: $command
Reason: $($_.Exception.Message)
Need user decision: yes
"@
        Add-IssueComment -Body $failed
    }
}

Write-Host 'Office Codex Issue Monitor started.'
Write-Host "Repo: $Owner/$Repo Issue #$IssueNumber Poll: $PollSeconds sec"
Write-Host "Runner: $RunnerScript"
Write-Host 'Triggers: @office-codex, notify-C, check-C, plus Chinese aliases.'

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
            Save-ProcessedIds -Map $processed
        }
    } catch {
        Write-Host ('Monitor error: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSeconds
}
