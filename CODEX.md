# Codex Instructions for KY-A3A

## Collaboration Style

- Treat GitHub issue #1 as the mobile inbox for instructions from the user.
- Accept short mobile inbox comments as actionable when they mention `@office-codex`, `Codex`, or a known project name.
- Treat `通知C` as an alias for `@office-codex`; the task text follows after `通知C`.
- When a new mobile instruction appears, acknowledge it in the issue before doing work.
- Before editing, inspect the repository and summarize the intended files to change.
- Keep changes small and reviewable.
- Prefer pull requests instead of direct commits to `main`.
- If a task requires credentials, deployment, external services, or destructive operations, stop and ask for confirmation.

## Project Safety

- Never commit `.env`, API keys, cookies, tokens, or private certificates.
- Keep examples in `.env.example`.
- Add or update validation steps whenever implementation files are added.

## Suggested First Task

Inspect the repository and propose the smallest runnable project skeleton for the intended product.
