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
2. Go to Codex.
3. Select this GitHub repository.
4. Start with ask mode for inspection.
5. Use code mode only after reviewing the proposed file changes.

## Safety rules

- Do not commit secrets or API keys.
- Use `.env.example` for environment variable names only.
- Prefer pull requests over direct commits to `main`.
- Run tests or validation before proposing a PR when a test command exists.
