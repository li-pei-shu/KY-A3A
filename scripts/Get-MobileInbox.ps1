param(
  [string]$Repo = "li-pei-shu/KY-A3A",
  [int]$Issue = 1,
  [int]$Limit = 10
)

$ErrorActionPreference = "Stop"

$credInput = "protocol=https`nhost=github.com`n`n"
$cred = $credInput | git credential fill
$tokenLine = $cred | Where-Object { $_ -like "password=*" } | Select-Object -First 1

if (-not $tokenLine) {
  throw "No GitHub credential found. Sign in to GitHub with Git Credential Manager first."
}

$token = $tokenLine.Substring("password=".Length)
$headers = @{
  Authorization = "Bearer $token"
  Accept = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
  "User-Agent" = "KY-A3A-Mobile-Inbox"
}

$issueUri = "https://api.github.com/repos/$Repo/issues/$Issue"
$commentsUri = "https://api.github.com/repos/$Repo/issues/$Issue/comments?per_page=$Limit"

$issueData = Invoke-RestMethod -Method Get -Uri $issueUri -Headers $headers
$comments = Invoke-RestMethod -Method Get -Uri $commentsUri -Headers $headers

"# $($issueData.title)"
"URL: $($issueData.html_url)"
"State: $($issueData.state)"
"Updated: $($issueData.updated_at)"
""
"## Latest comments"

if (-not $comments -or $comments.Count -eq 0) {
  "(no comments yet)"
  exit 0
}

$comments |
  Sort-Object created_at -Descending |
  Select-Object -First $Limit |
  ForEach-Object {
    ""
    "[$($_.created_at)] @$($_.user.login)"
    $_.body
  }
