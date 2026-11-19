---
name: me_draft
description: Commit any uncommitted work, push, and create or update a draft PR against main.
---

# me: draft

Commit any uncommitted work, push commits, and create or update a draft PR.

Do **not** wait for confirmation. Commit, push, and open or update the PR immediately.

## 0. Pre-commit check

- If a restyled view or `app/frontend/stylesheets/app.tailwind.css` changed, run `npm run build:css:app` and include `public/app-tailwind.css`. If marketing styles changed, run `npm run build:css` and include `public/marketing.css`.
- This repo has no Standard, ERB lint, ESLint, or Brakeman step. Don't run them.

## 1. Commit uncommitted work

- Prepend `GIT_EDITOR=true` to git commands, especially ones that look at diffs.
- If `git diff` or `git diff --cached` fails, stop and report a blocker. Do not infer changes from working memory.
- If the working tree and the index are clean, skip the commit. That is the normal case after `/me_commit`. The change set to push is `git diff origin/main...HEAD`. If that is empty too, stop and say there is nothing to push.
- If there are uncommitted changes, commit them only after `git diff` and `git diff --cached` show those changes. The pushed set is then `git diff origin/main...HEAD`.
- If those commits are on local `main`, move them onto a feature branch before the push, using the rules below. Nobody pushes to `main`.

**Branch before committing or pushing when the work is on `main`.** Every change reaches `main` through a PR.

- Already on a feature branch: stay there. Do not open a second branch for a follow-up or a review fix.
- On `main` with uncommitted work: create `<user>/<short-description>` (for example `paul/<short-description>`) at the current commit **before** committing, then commit on that branch.
- If the commit is already on local `main` and has **not** been pushed: create `<user>/<short-description>` at that commit, check it out, then point local `main` back at origin (`git branch -f main origin/main`). Never reset a commit that is already pushed.

Review each file individually to make sure it belongs to this work, then write a brief commit message:

- Short title (< 80 characters)
- 2–3 bullets (< 80 characters) describing the change

Never commit `.env`, encryption keys, or `config/secrets.yml`. If a pre-commit hook fails, fix the cause and make a new commit. Never `--no-verify`, and never amend a pushed commit.

## 2. Push

- If the branch is not pushed: `git push -u origin HEAD`
- If it already tracks: `git push`
- If push fails because the remote moved: `git pull --rebase origin <branch>`, resolve, then push. Abort the rebase if you should abandon it.

## 3. PR

In a Claude Code cloud session (`CLAUDE_CODE_REMOTE=true`), `gh pr …` and GraphQL fail. Use the REST forms in `.agents/skills/README.md` for each `gh pr` step.

Check for an existing PR:

```bash
gh pr list --head <branch> --state open --json number,title,body,headRefName,isDraft,baseRefName
```

This command opens and updates **draft** PRs only. `/me_ship` is what marks a PR ready, waits for CI, and merges it.

**Base branch:** every PR targets `main`. Pass `--base main` on create. Retarget anything else with `gh pr edit <number> --base main`. Do not create a new branch when updating an existing PR.

**Title:** a concise, user-facing title that summarizes the whole change.

**New PR:**

- Review `git diff origin/main...HEAD` and `git log origin/main..HEAD`.
- Read `.agents/skills/me_template.md`. The body starts with "Flags for human review".
- Create it as a **draft** with `gh pr create --draft --base main`. Don't wait for confirmation, and don't mark it ready.
- Return the PR URL.

**Existing PR:**

- Push, then retitle with `gh pr edit` when the current title no longer covers the full scope.
- Update the description to match the commits. Refresh "Flags for human review" and keep human edits to it.
- Leave the PR **draft**.

## 4. Report

PR URL, draft status, and anything left unstaged. Next step is more work, or `/me_ship` to take this branch to production.
