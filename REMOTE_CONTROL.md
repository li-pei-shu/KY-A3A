# Office Codex Remote Control Mode

This repo uses GitHub issue #1 as a lightweight remote-control bridge:

```text
mobile GPT -> GitHub issue #1 -> office Codex -> GitHub issue #1
```

It is not a live desktop remote session. It is an instruction queue with automatic status replies.

## Teach Mobile GPT Once

Paste this once into the mobile GPT conversation you want to use:

```text
你是我的辦公室 Codex 遙控器。

規則：
1. 當我說「通知C：<任務>」，請使用 GitHub 在 li-pei-shu/KY-A3A 的 issue #1 留言：「@office-codex <任務>」。
2. 當我說「查C：<專案或任務>」，請使用 GitHub 在 li-pei-shu/KY-A3A 的 issue #1 留言：「@office-codex status <專案或任務>」。
3. 不要把我的短句改成很長的表格，除非我明確要求。
4. 不要要求我提供 GitHub 帳密。
```

## Daily Commands

Use short commands from mobile:

```text
通知C：3D建模整理1530個pending decisions的分類與處理順序
查C：3D建模
通知C：KY官網今天先整理待辦，不修改檔案
通知C：LINE bot 檢查部署狀態，不要真的部署
```

## Office Codex Behavior

When a new command appears, office Codex should:

1. Read the newest issue #1 comments.
2. Ignore comments already followed by an Office Codex `Status:` reply.
3. Acknowledge the newest unhandled command.
4. If the request is safe and specific, do the work.
5. If the request is risky or underspecified, ask one concise confirmation question.
6. Reply with progress and result in issue #1.

## Safe To Execute Without Asking

- Progress reports.
- Reading files and project state.
- Running non-destructive status commands.
- Running existing tests when the user asks for validation.
- Creating a report or plan file inside an explicitly named project.

## Ask Before Acting

- Deployments.
- Deleting files or resetting Git.
- Sending secrets, tokens, cookies, or private data.
- Creating a new GitHub repo when the repo name or owner is unclear.
- Writing outside an explicit project path.
- Broad changes where the target project is unclear.

## Default Status Reply

```text
Status: received.
Task:
Current state:
Progress:
Blocked by:
Next step:
Need user decision:
```

