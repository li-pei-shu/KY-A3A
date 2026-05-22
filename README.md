# KY-A3A

KY-A3A is the GitHub workspace and relay center for mobile GPT to control the office Codex environment.

## Core workflow

```text
mobile GPT -> GitHub Issue -> office relay -> Codex CLI -> GitHub reply -> mobile GPT summary
```

## Command roles

- `修G`: GPT handles GitHub repo edits directly.
- `通知C`: GPT posts a task to the Office Codex relay inbox.
- `查C`: GPT reads `STATUS.md` first and reports the latest task status.
- `維修C`: use mobile SSH only when the relay itself needs repair.

## Current status source

Use `STATUS.md` as the first source for mobile status checks. Issue comments are historical logs and are used only when deeper debugging is needed.

## Relay scripts

- `scripts/Start-OfficeCodexRelay.ps1`: start, stop, restart, status, logs, and runner test.
- `scripts/office-codex-issue-monitor.ps1`: watches the inbox issue and dispatches work to the runner.
- `scripts/Invoke-OfficeCodexTask.ps1`: calls Codex CLI for safe local tasks.
- `scripts/Get-MobileInbox.ps1`: reads issue comments for debugging.

## Mobile use

Daily operation should happen from mobile GPT:

```text
通知C：檢查 KY-A3A 狀態，不要修改檔案
查C：目前任務
修G：更新 README
維修C：查看中繼站狀態
```

## Safety

- Do not put private credentials in GitHub issues.
- Use GitHub issues for tasks, status, and links only.
- Use mobile SSH only for relay repair.
