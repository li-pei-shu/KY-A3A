# Office Codex GitHub Relay

目標：讓手機 GPT 透過 GitHub Issue #1 傳話給辦公室 Codex，且每個指令都有明確回覆，不再單向溝通。

## 指令入口

Repo: `li-pei-shu/KY-A3A`
Issue: `#1 Mobile Inbox: instructions for Office Codex`

手機端可輸入：

```text
通知C：<任務>
查C：<專案或任務>
```

ChatGPT 會轉成 Issue #1 留言：

```text
@office-codex <任務>
@office-codex status <專案或任務>
```

## 必須有三段回覆

### 1. GitHub 收件

由 GitHub Actions workflow `mobile-inbox-ack.yml` 回覆：

```text
Status: received by GitHub bridge.
```

代表 GPT 已成功把指令送到 GitHub，但不代表辦公室 Codex 已讀取。

### 2. Office Codex 收件

由辦公室 monitor 回覆：

```text
Status: received by Office Codex.
Task source comment: #<comment_id>
Command: <parsed command>
```

代表辦公室端已讀到指令。

### 3. Office Codex 結果

由辦公室 monitor 或 Codex 回覆：

```text
Status: done | working | blocked | failed
Task source comment: #<comment_id>
Result: ...
Need user decision: yes | no
Next step: ...
```

這才代表 Codex 已處理或明確卡住。

## 判斷表

| 訊息 | 意義 |
|---|---|
| `Status: received by GitHub bridge` | GitHub 收到，但 C 未必讀到 |
| `Status: received by Office Codex` | C 已讀到 |
| `Status: working` | C 正在處理 |
| `Status: done` | C 完成 |
| `Status: blocked` | C 收到，但需要決策 |
| 只有 GPT 留言，沒有任何 received | GitHub/Actions 或 monitor 有問題 |

## 辦公室端最低要求

1. `codexwindows` 必須開機。
2. Tailscale 或網路必須可用。
3. Office Codex monitor 必須執行。
4. Monitor 必須能讀 GitHub Issue #1。
5. Monitor 必須能在 Issue #1 回覆 comment。

## 建議啟動方式

在辦公室 Windows 執行：

```powershell
cd C:\Users\st\OneDrive\文件\3D建模\a3a
powershell -ExecutionPolicy Bypass -File .\scripts\office-codex-issue-monitor.ps1
```

若要常駐，請建立 Windows Scheduled Task 或 GitHub self-hosted runner。

## 安全限制

- 不要在 Issue 裡貼密碼、token、key。
- 部署、刪除、付費、改 SSH 系統設定前，必須先回報並等待確認。
- 一般查詢、狀態回報、讀檔分析可以直接處理。
