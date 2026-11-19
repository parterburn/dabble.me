---
name: me_commit
description: Commit the current work locally without pushing or opening a PR, so you can keep working before /me_draft or /me_ship.
---

# me: commit

Save a checkpoint: check the uncommitted work on the current feature branch, then commit and stop. Use it when a piece of work is done but the PR isn't ready yet. Later, `/me_draft` or `/me_ship` pushes these commits and opens the PR.

Do **not** wait for confirmation; commit immediately. Do **not** push or open a PR.

## 0. Pre-commit check

- Prefix every git command with `GIT_EDITOR=true`.
- `git status --short`. Nothing to commit: say so and stop.
- If `git diff` fails or returns no usable change set, stop and report a blocker. Do not infer changes from working memory.
- If a restyled view or `app/frontend/stylesheets/app.tailwind.css` changed, run `npm run build:css:app` and include `public/app-tailwind.css`. If marketing styles changed, run `npm run build:css` and include `public/marketing.css`.
- This repo has no Standard, ERB lint, ESLint, or Brakeman step. Don't run them.
- Specs are not rerun here unless code changed since the last spec run in this conversation. Then run the specs for the touched files, skipping `js: true`, with the command in `.agents/skills/me_ship/SKILL.md` step 3.

## 1. Branch

Same rules as `/me_draft` step 1:

- On a feature branch: stay there.
- On `main`: create `<user>/<short-description>` at the current commit before committing. Nobody commits to `main`.

## 2. Commit

- Review each changed and untracked file and stage only the ones that belong to this work (`git add <paths>`, never a blind `git add -A` over unrelated files). If unrelated changes are present, leave them unstaged and list them in the report.
- Message:
  - a short title (< 80 characters)
  - 2–3 bullets (< 80 characters each) on what changed
  - the commit attribution trailer the harness asks for, if any
- Commit. If a pre-commit hook fails, fix the cause and make a new commit; never `--no-verify`, and never amend a commit that is already pushed.
- Never commit `.env`, encryption keys, or `config/secrets.yml`.

## 3. Report

- The commit hash and title, the files in it, and anything left unstaged.
- How many commits the branch is ahead of `origin/main`, and that none are pushed.
- Next step: keep working and `/me_commit` again, or `/me_draft` to push and open a draft PR, or `/me_ship` to take it to production.
