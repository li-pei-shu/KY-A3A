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
        (([string][char]0x90E8) + ([string][char]0x7F72)), # deploy
        (([string][char]0x522A) + ([string][char]0x9664)), # delete, traditional
        (([string][char]0x5220) + ([string][char]0x9664)), # delete, simplified
        (([string][char]0x79FB) + ([string][char]0x9664)), # remove
        (([string][char]0x63A8) + ([string][char]0x9001)), # push
        (([string][char]0x5BC6) + ([string][char]0x78BC)), # password, traditional
        (([string][char]0x5BC6) + ([string][char]0x7801)), # password, simplified
        (([string][char]0x6191) + ([string][char]0x8B49)), # credential, traditional
        (([string][char]0x51ED) + ([string][char]0x8BC1)), # credential, simplified
        (([string][char]0x91D1) + ([string][char]0x9470)), # key, traditional
        (([string][char]0x5BC6) + ([string][char]0x94A5))  # key, simplified
    )

    foreach ($term in $literalUnsafeTerms) {
        if ($Text.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $term }
    }

    return $null

<#
    $patterns = @(
        '(?i)\bdeploy\b',
        '(?i)\bdelete\b',
        '(?i)\bremove\b',
        '(?i)\brm\s+-rf\b',
        '(?i)\bpush\s+main\b',
        '(?i)\bgit\s+push\b',
        '(?i)\bsecret\b',
        '(?i)\btoken\b',
        '(?i)\bpassword\b',
        '(?i)\bapi[_-]?key\b',
        '部署',
        '刪除',
        '移除',
        '推送\s*main',
        '密碼',
        '憑證',
        '權杖',
        '金鑰',
        '付費',
        '付款',
        '系統設定'
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) { return $pattern }
    }
    return $null
#>
}

function Get-SafeOutputTail {
    param(
        [string[]]$Lines,
        [int]$MaxLines = 80,
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

    $sensitiveEnvNames = @(
        'GITHUB_TOKEN',
        'OFFICE_CODEX_GITHUB_TOKEN',
        'OPENAI_API_KEY',
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
        Push-Location $WorkDir
        try {
            $output = & $codexCommand.Source exec --cd $WorkDir $codexPrompt 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
    } finally {
        foreach ($name in $sensitiveEnvNames) {
            if ($null -ne $savedEnv[$name]) {
                [Environment]::SetEnvironmentVariable($name, $savedEnv[$name], 'Process')
            }
        }
    }

    $lines = @($output | ForEach-Object { [string]$_ })
    $tail = Get-SafeOutputTail -Lines $lines

    if ($exitCode -eq 0) {
        New-Result -Status 'done' -ExitCode $exitCode -Summary 'Codex CLI completed successfully.' -OutputTail $tail
    } else {
        New-Result -Status 'failed' -ExitCode $exitCode -Reason 'Codex CLI returned a non-zero exit code.' -OutputTail $tail
    }
} catch {
    New-Result -Status 'failed' -Reason $_.Exception.Message
    exit 0
}
