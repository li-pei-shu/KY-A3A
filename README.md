# KY-A3A

This repository is prepared for Codex Cloud + GitHub workflows.

## Purpose

Use this repo as the working area for the KY-A3A project. Codex can read the repository, propose changes, create branches, and prepare pull requests for review.

## Recommended first Codex task

Ask Codex Cloud:

```text
Please inspect this repository first. Do not modify files yet. Summarize the project state, identify missing files needed for a runnable app, and propose a small first implementation plan.
```

## Mobile workflow

1. Open ChatGPT on mobile.
2. Use Codex Cloud in the mobile browser, or use ChatGPT with GitHub access.
3. Send instructions through the Mobile Inbox issue when the office Codex app should continue work.
4. Use `MOBILE_HANDOFF.md` for the exact message format.
5. Start with ask mode for inspection when using Codex Cloud.

Mobile Inbox:

https://github.com/li-pei-shu/KY-A3A/issues/1

Quick mobile command:

```text
請到 KY-A3A issue #1 留言：@office-codex 3D建模進度回報，不改檔不部署。
```

Shortcut alias:

```text
通知C：3D建模進度回報
```

Alias rule:

```text
通知C：<任務> = GitHub issue #1 comment: @office-codex <任務>
```

## Safety rules

- Do not commit secrets or API keys.
- Use `.env.example` for environment variable names only.
- Prefer pull requests over direct commits to `main`.
- Run tests or validation before proposing a PR when a test command exists.
