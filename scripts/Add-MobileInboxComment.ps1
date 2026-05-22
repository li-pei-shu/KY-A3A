param(
  [Parameter(Mandatory = $true)]
  [string]$Body,
  [string]$Repo = "li-pei-shu/KY-A3A",
  [int]$Issue = 1
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

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

$uri = "https://api.github.com/repos/$Repo/issues/$Issue/comments"
$payload = @{ body = $Body } | ConvertTo-Json -Compress
$result = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $payload -ContentType "application/json"

"comment_url=$($result.html_url)"
