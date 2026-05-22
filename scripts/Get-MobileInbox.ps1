param(
  [string]$Repo = $(if ($env:GITHUB_REPO) { $env:GITHUB_REPO } else { 'li-pei-shu/KY-A3A' }),
  [int]$Issue = $(if ($env:MOBILE_INBOX_ISSUE_NUMBER) { [int]$env:MOBILE_INBOX_ISSUE_NUMBER } else { 1 }),
  [int]$Limit = 10
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

$issueUri = "https://api.github.com/repos/$Repo/issues/$Issue"
$commentsUri = "https://api.github.com/repos/$Repo/issues/$Issue/comments?per_page=100"

$issueData = Invoke-RestMethod -Method Get -Uri $issueUri -Headers $headers
$comments = Invoke-RestMethod -Method Get -Uri $commentsUri -Headers $headers

"# $($issueData.title)"
"URL: $($issueData.html_url)"
"State: $($issueData.state)"
"Updated: $($issueData.updated_at)"
""
"## Latest comments"

if (-not $comments -or $comments.Count -eq 0) {
  '(no comments yet)'
  exit 0
}

$comments |
  Sort-Object created_at -Descending |
  Select-Object -First $Limit |
  ForEach-Object {
    ''
    "[$($_.created_at)] @$($_.user.login)"
    $_.body
  }
