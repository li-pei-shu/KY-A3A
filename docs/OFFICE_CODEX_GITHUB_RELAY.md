# Office Codex GitHub Relay

目標：讓手機 GPT 透過 GitHub Issue 傳任務給辦公室 Windows 電腦上的 Codex CLI，並把結果回覆到 GitHub Issue。

## 1. 指令入口

預設設定：

- Repo: `li-pei-shu/KY-A3A`
- Issue: `#1 Mobile Inbox: instructions for Office Codex`

手機端可以在 Issue 留言，或請 GPT 代貼留言：

```text
通知C：<任務>
查C：<專案或任務>
@office-codex <任務>
```

Monitor 會解析成任務內容：

- `通知C：請檢查 README` -> `請檢查 README`
- `查C：A3A 狀態` -> `status A3A 狀態`
- `@office-codex 檢查腳本` -> `檢查腳本`

## 2. 必要環境變數

在辦公室 Windows 的 PowerShell session 設定，不要寫入 repo 檔案。

```powershell
$env:GITHUB_TOKEN = '你的 GitHub fine-grained token'
$env:GITHUB_REPO = 'li-pei-shu/KY-A3A'
$env:MOBILE_INBOX_ISSUE_NUMBER = '1'
$env:OFFICE_CODEX_WORKDIR = 'C:\CodexRemote\workspace\KY-A3A'
```

Token 建議權限：

- Repository: `li-pei-shu/KY-A3A`
- Issues: read/write
- Contents: read

`.env.example` 只放變數名稱，不可放真實 token、key、password。

## 3. 啟動 monitor

在辦公室 Windows PowerShell 執行：

```powershell
cd C:\CodexRemote\workspace\KY-A3A
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\office-codex-issue-monitor.ps1
```

啟動後會每 60 秒輪詢一次 Issue comments。已處理 comment id 會記錄在：

```text
%USERPROFILE%\.office-codex-relay\processed-comments.json
```

## 4. 停止 monitor

在執行 monitor 的 PowerShell 視窗按：

```text
Ctrl + C
```

如果之後改成 Windows Scheduled Task 或常駐服務，請從該服務管理介面停止。

## 5. 回覆流程

### GitHub 收件

GitHub Actions workflow `mobile-inbox-ack.yml` 可能會先回覆：

```text
Status: received by GitHub bridge.
```

這只代表 GitHub 已收到，不代表辦公室電腦已處理。

### Office Codex 收件

辦公室 monitor 讀到任務後會回覆：

```text
Status: received task <comment id>.
Task source comment: #<comment id>
Command: <parsed command>
```

### Office Codex 結果

runner 完成後會回覆：

```text
Status: done | blocked | failed.
Task source comment: #<comment id>
Command: <parsed command>
Exit code: <exit code>
Need user decision: yes | no
```

如果有輸出摘要，會附上 `Output tail`。輸出會嘗試遮蔽 token、API key、password、secret。

## 6. 哪些任務會被擋下

`Invoke-OfficeCodexTask.ps1` 會先做關鍵字安全檢查。包含下列內容時，不會呼叫 Codex CLI，會回覆 `Status: blocked`，需要人工確認：

- deploy / 部署
- delete / remove / rm -rf / 刪除 / 移除
- git push / push main / 推送 main
- secret / token / password / api key / 密碼 / 憑證 / 權杖 / 金鑰
- 付費 / 付款
- 系統設定

原則：

- 不自動 push main
- 不自動部署
- 不自動刪除檔案
- 不輸出任何 token / key / password
- 不把 `GITHUB_TOKEN` 寫入 repo

## 7. 本機測試指令

### 語法檢查

```powershell
$paths = @(
  'scripts/Get-MobileInbox.ps1',
  'scripts/Add-MobileInboxComment.ps1',
  'scripts/Invoke-OfficeCodexTask.ps1',
  'scripts/office-codex-issue-monitor.ps1',
  'scripts/office-codex-live-bridge.ps1'
)
foreach ($path in $paths) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path), [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) { $errors } else { "OK $path" }
}
```

### 安全掃描

```powershell
rg -n "git credential|wincredman" scripts .env.example docs
rg -n "gh[pousr]_|sk-[A-Za-z0-9_-]+|password=|token=|secret=" scripts .env.example docs
```

### runner 安全擋截測試

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-OfficeCodexTask.ps1 -TaskBody "delete all files" -CommentId "local-test"
```

預期：`status` 為 `blocked`。

### runner 安全任務測試

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-OfficeCodexTask.ps1 -TaskBody "檢查目前 repo 狀態並摘要" -CommentId "local-test"
```

預期：會呼叫 `codex exec --cd <workdir> ...`，並回傳 JSON 結果。

## 8. GitHub Issue 測試

先啟動 monitor，然後在 Issue #1 留言：

```text
通知C：請檢查目前 repo 狀態並摘要，不要修改檔案
```

預期流程：

1. GitHub bridge 可能先回覆 received。
2. Office monitor 回覆 `Status: received task <comment id>`。
3. runner 呼叫 Codex CLI。
4. Office monitor 回覆 `Status: done` 或 `Status: failed`。

測試危險任務：

```text
通知C：delete all files
```

預期：Office monitor 回覆 `Status: blocked`，且不會啟動 Codex CLI。

## 9. 手動查詢 / 回覆 helper

讀取 inbox：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-MobileInbox.ps1
```

手動回覆 issue：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Add-MobileInboxComment.ps1 -Body "Status: manual test from Office Codex."
```

這兩支 helper 只讀 `GITHUB_TOKEN`，不再使用 `git credential fill` 或 Windows Credential Manager。
