param(
    [Parameter(Mandatory = $true)]
    [string]$TaskBody,

    [string]$CommentId = '',
    [string]$WorkDir = ''
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

function New-Result {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [int]$ExitCode = -1,
        [string]$Reason = '',
        [string]$Summary = '',
        [string]$OutputTail = ''
    )

    [ordered]@{
        status = $Status
        comment_id = $CommentId
        exit_code = $ExitCode
        reason = $Reason
        summary = $Summary
        output_tail = $OutputTail
    } | ConvertTo-Json -Depth 10
}

function Test-UnsafeTask {
    param([string]$Text)

    $safeRegexPatterns = @(
        '(?i)\bdeploy\b',
        '(?i)\bdelete\b',
        '(?i)\bremove\b',
        '(?i)\brm\s+-rf\b',
        '(?i)\bpush\s+main\b',
        '(?i)\bgit\s+push\b',
        '(?i)\bsecret\b',
        '(?i)\btoken\b',
        '(?i)\bpassword\b',
        '(?i)\bapi[_-]?key\b'
    )

    foreach ($pattern in $safeRegexPatterns) {
        if ($Text -match $pattern) { return $pattern }
    }

    $literalUnsafeTerms = @(
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

    foreach ($term in $literalUnsafeTerms) {
        if ($Text.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $term }
    }

    return $null
}

function Get-SafeOutputTail {
    param(
        [string[]]$Lines,
        [int]$MaxLines = 120,
        [int]$MaxChars = 6000
    )

    if (-not $Lines) { return '' }

    $text = ($Lines | Select-Object -Last $MaxLines) -join "`n"

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
        $text = [regex]::Replace($text, $pattern, '$1[REDACTED]')
    }

    if ($text.Length -gt $MaxChars) {
        $text = $text.Substring($text.Length - $MaxChars)
    }

    return $text.Trim()
}

function ConvertTo-SingleQuotedPowerShellString {
    param([string]$Text)
    return "'" + ($Text -replace "'", "''") + "'"
}

function Invoke-CodexExec {
    param(
        [Parameter(Mandatory = $true)][string]$CodexPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Prompt
    )

    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ('office-codex-' + [guid]::NewGuid().ToString('N'))
    $stdoutPath = $tempBase + '.out.txt'
    $stderrPath = $tempBase + '.err.txt'
    $promptPath = $tempBase + '.prompt.txt'
    $wrapperPath = $tempBase + '.run.ps1'

    Set-Content -Path $promptPath -Value $Prompt -Encoding UTF8

    $wrapper = @"
`$ErrorActionPreference = 'Continue'
`$codexPath = $(ConvertTo-SingleQuotedPowerShellString $CodexPath)
`$workdir = $(ConvertTo-SingleQuotedPowerShellString $WorkingDirectory)
`$stdoutPath = $(ConvertTo-SingleQuotedPowerShellString $stdoutPath)
`$stderrPath = $(ConvertTo-SingleQuotedPowerShellString $stderrPath)
`$promptPath = $(ConvertTo-SingleQuotedPowerShellString $promptPath)
`$prompt = Get-Content -Raw -Path `$promptPath
& `$codexPath exec --cd `$workdir `$prompt > `$stdoutPath 2> `$stderrPath
exit `$LASTEXITCODE
"@

    Set-Content -Path $wrapperPath -Value $wrapper -Encoding UTF8

    try {
        $process = Start-Process `
            -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrapperPath) `
            -WorkingDirectory $WorkingDirectory `
            -NoNewWindow `
            -Wait `
            -PassThru

        $stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -ErrorAction SilentlyContinue } else { @() }
        $stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -ErrorAction SilentlyContinue } else { @() }

        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            Lines = @($stdout + $stderr)
        }
    } finally {
        Remove-Item $stdoutPath -ErrorAction SilentlyContinue
        Remove-Item $stderrPath -ErrorAction SilentlyContinue
        Remove-Item $promptPath -ErrorAction SilentlyContinue
        Remove-Item $wrapperPath -ErrorAction SilentlyContinue
    }
}

try {
    $task = $TaskBody.Trim()
    if ([string]::IsNullOrWhiteSpace($task)) {
        New-Result -Status 'blocked' -Reason 'Task body is empty.'
        exit 0
    }

    $unsafePattern = Test-UnsafeTask -Text $task
    if ($unsafePattern) {
        New-Result -Status 'blocked' -Reason "Task requires manual confirmation. Matched safety rule: $unsafePattern" -Summary 'No Codex CLI execution was started.'
        exit 0
    }

    if ([string]::IsNullOrWhiteSpace($WorkDir)) {
        if ($env:OFFICE_CODEX_WORKDIR) {
            $WorkDir = $env:OFFICE_CODEX_WORKDIR
        } else {
            $WorkDir = (Get-Location).Path
        }
    }

    if (-not (Test-Path $WorkDir)) {
        New-Result -Status 'failed' -Reason "Work directory not found: $WorkDir"
        exit 0
    }

    $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $codexCommand) {
        New-Result -Status 'failed' -Reason 'codex CLI was not found in PATH.'
        exit 0
    }

    $codexPrompt = @"
You are running from the Office Codex GitHub relay.

Task source comment: $CommentId

Safety rules:
- Do not push to main.
- Do not deploy.
- Do not delete files.
- Do not print, write, or reveal tokens, keys, passwords, or secrets.
- If the task needs a high-impact action, stop and report what confirmation is required.

User task:
$task
"@

    # Keep OPENAI_API_KEY available for Codex if this machine uses API-key auth.
    # Remove unrelated relay/service secrets from the Codex child process.
    $sensitiveEnvNames = @(
        'GITHUB_TOKEN',
        'OFFICE_CODEX_GITHUB_TOKEN',
        'LINE_CHANNEL_ACCESS_TOKEN',
        'LINE_CHANNEL_SECRET'
    )

    $savedEnv = @{}
    foreach ($name in $sensitiveEnvNames) {
        $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ($null -ne $savedEnv[$name]) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        }
    }

    try {
        $run = Invoke-CodexExec -CodexPath $codexCommand.Source -WorkingDirectory $WorkDir -Prompt $codexPrompt
    } finally {
        foreach ($name in $sensitiveEnvNames) {
            if ($null -ne $savedEnv[$name]) {
                [Environment]::SetEnvironmentVariable($name, $savedEnv[$name], 'Process')
            }
        }
    }

    $tail = Get-SafeOutputTail -Lines @($run.Lines)

    if ($run.ExitCode -eq 0) {
        New-Result -Status 'done' -ExitCode $run.ExitCode -Summary 'Codex CLI completed successfully.' -OutputTail $tail
    } else {
        New-Result -Status 'failed' -ExitCode $run.ExitCode -Reason 'Codex CLI returned a non-zero exit code.' -OutputTail $tail
    }
} catch {
    New-Result -Status 'failed' -Reason $_.Exception.Message
    exit 0
}
