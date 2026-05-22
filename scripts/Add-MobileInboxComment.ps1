param(
  [Parameter(Mandatory = $true)]
  [string]$Body,
  [string]$Repo = $(if ($env:GITHUB_REPO) { $env:GITHUB_REPO } else { 'li-pei-shu/KY-A3A' }),
  [int]$Issue = $(if ($env:MOBILE_INBOX_ISSUE_NUMBER) { [int]$env:MOBILE_INBOX_ISSUE_NUMBER } else { 1 })
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
  throw 'Missing GITHUB_TOKEN environment variable.'
}

$headers = @{
  Authorization = "Bearer $env:GITHUB_TOKEN"
  Accept = 'application/vnd.github+json'
  'X-GitHub-Api-Version' = '2022-11-28'
  'User-Agent' = 'KY-A3A-Mobile-Inbox'
}

$uri = "https://api.github.com/repos/$Repo/issues/$Issue/comments"
$payload = @{ body = $Body } | ConvertTo-Json -Compress
$result = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $payload -ContentType 'application/json'

"comment_url=$($result.html_url)"
