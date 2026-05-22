# Mobile to Office Codex Handoff

Use GitHub as the handoff channel between mobile ChatGPT/Codex Cloud and the office Codex app.

For the shorter remote-control style, see `REMOTE_CONTROL.md`.

## Inbox

Primary inbox issue:

https://github.com/li-pei-shu/KY-A3A/issues/1

## Mobile Message Format

For daily use, send a short instruction. Office Codex will treat short comments in issue #1 as actionable when they mention Codex or an existing project name.

## Shortcut Alias

Teach mobile ChatGPT this once:

```text
你是我的辦公室 Codex 遙控器。
當我說「通知C：<任務>」，你就使用 GitHub 在 li-pei-shu/KY-A3A 的 issue #1 留言：「@office-codex <任務>」。
當我說「查C：<專案或任務>」，你就使用 GitHub 在 li-pei-shu/KY-A3A 的 issue #1 留言：「@office-codex status <專案或任務>」。
不要把我的短句改成很長的表格，除非我明確要求。
```

Then daily use can be this short:

```text
通知C：3D建模進度回報
```

Expected GitHub issue comment:

```text
@office-codex 3D建模進度回報
```

Office Codex also accepts direct issue comments that start with `通知C`.
`查C` is the status-only command.

## Quick Examples

Shortest useful mobile prompt without alias setup:

```text
請到 KY-A3A issue #1 留言：@office-codex 3D建模進度回報，不改檔不部署。
```

Other quick examples after alias setup:

```text
通知C：報修系統進度回報
通知C：LINE bot 檢查部署狀態，不要真的部署
通知C：KY官網今天先整理待辦，不修改檔案
```

Use the full format only when the request is complex:

```text
@office-codex
Action: <what you want office Codex to do>
Scope: <repo/file/system/service>
Priority: normal | urgent
Constraints: <do not deploy / do not push / ask before changing files / etc.>
Expected result: <what reply or output you want>
```

## Office Codex Workflow

1. Read the newest comments in the inbox issue.
2. Acknowledge the instruction by commenting on the issue.
3. Pull the latest repository state before making changes.
4. Perform only the requested work.
5. Comment back with status, files changed, commands/tests run, and any links to commits or pull requests.
6. If the request involves secrets, deployment, destructive commands, or external paid services, stop and ask first.

## Office Helper Scripts

Read the latest inbox comments:

```powershell
.\scripts\Get-MobileInbox.ps1
```

Reply back to the inbox:

```powershell
.\scripts\Add-MobileInboxComment.ps1 -Body "Status: received. I am checking this now."
```

## Recommended Mobile Prompt

Use this in mobile ChatGPT:

```text
Using GitHub, add a comment to li-pei-shu/KY-A3A issue #1 with this instruction for office Codex:

@office-codex
Action:
Scope:
Priority: normal
Constraints:
Expected result:
```

## Safety

- Do not put passwords, API keys, cookies, tokens, or private customer data in GitHub issues.
- Use GitHub issue comments for instructions, status, and links only.
- Use `.env.example` for environment variable names, not real values.
