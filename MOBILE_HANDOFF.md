# Mobile to Office Codex Handoff

Use GitHub as the handoff channel between mobile ChatGPT/Codex Cloud and the office Codex app.

## Inbox

Primary inbox issue:

https://github.com/li-pei-shu/KY-A3A/issues/1

## Mobile Message Format

Add a new comment to the inbox issue:

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
