# Agent skills

Shared skill definitions for agent harnesses. Each `me_*` folder is a full skill
(YAML frontmatter + workflow steps). `modern-web-guidance` is a separate reference
skill and is not part of the ship workflow.

Claude Code and Cursor load the ship skills through symlinks under `.claude/skills/`
(for example `.claude/skills/me_ship` → `../../.agents/skills/me_ship`).

| Workflow | Skill |
|---|---|
| `me_commit` | [me_commit/SKILL.md](me_commit/SKILL.md) |
| `me_draft` | [me_draft/SKILL.md](me_draft/SKILL.md) |
| `me_ship` | [me_ship/SKILL.md](me_ship/SKILL.md) |
| `me_review` | [me_review/SKILL.md](me_review/SKILL.md) |
| `me_feedback` | [me_feedback/SKILL.md](me_feedback/SKILL.md) |

`me_template.md` is the PR body template used by `me_ship`, `me_draft`, `me_review`,
and `me_feedback`.

## Adding a skill

Put the full definition in `.agents/skills/<name>/SKILL.md`, then symlink
`.claude/skills/<name>` → `../../.agents/skills/<name>`.

## GitHub commands in Claude Code cloud sessions

Claude Code cloud sessions (`CLAUDE_CODE_REMOTE=true`) cannot reach GitHub
GraphQL, so every `gh pr …` command and `gh api graphql` fail there with
`HTTP 403: GitHub GraphQL is not available from Claude Code sessions`. Locally,
keep using the `gh pr …` commands the skills give. In a cloud session, use these
instead. `git push` and `gh run …` work everywhere unchanged.

The repo is `parterburn/dabble.me`. The default branch is `main`.

Open PR for a branch (`gh pr list --head <branch>`):

```bash
gh api "repos/parterburn/dabble.me/pulls?head=parterburn:<branch>&state=open" --jq '.[] | {number, html_url, draft, base: .base.ref, body}'
```

Find a PR by text (`gh pr list --search`):

```bash
gh api -X GET search/issues -f q='repo:parterburn/dabble.me is:pr "<text>" in:title,body' --jq '.items[] | {number, html_url, state}'
```

Read a PR (`gh pr view <n>`):

```bash
gh api repos/parterburn/dabble.me/pulls/<n> --jq '{number, html_url, draft, state, merged, merge_commit_sha, body, base: .base.ref, head: .head.sha, mergeable, mergeable_state}'
gh api --paginate repos/parterburn/dabble.me/pulls/<n>/commits --jq '.[] | .commit.message'
```

Create a PR (`gh pr create --base main --body-file -`). Body on stdin. `draft: true` for a draft:

```bash
jq -n --arg t "<title>" --arg h "<branch>" --rawfile b /dev/stdin '{title: $t, head: $h, base: "main", body: $b, draft: false}' <<'BODY' | gh api -X POST repos/parterburn/dabble.me/pulls --input - --jq .html_url
<body>
BODY
```

Retarget, retitle, or replace the body (`gh pr edit`):

```bash
gh api -X PATCH repos/parterburn/dabble.me/pulls/<n> -f base=main
gh api -X PATCH repos/parterburn/dabble.me/pulls/<n> -f title="<title>"
gh api -X PATCH repos/parterburn/dabble.me/pulls/<n> -F body=@- <<'BODY'
<body>
BODY
```

Mark a draft ready (`gh pr ready <n>`):

```bash
gh api -X POST repos/parterburn/dabble.me/pulls/<n>/ccr/ready_for_review
```

Review threads:

```bash
gh api repos/parterburn/dabble.me/pulls/<n>/ccr/review_threads
gh api -X POST repos/parterburn/dabble.me/pulls/<n>/ccr/comments/<comment_id>/resolve
```

Reply to one review comment:

```bash
gh api -X POST repos/parterburn/dabble.me/pulls/<n>/comments/<comment_id>/replies -f body="<reply>"
```

Merge (`gh pr merge <n> --merge`):

```bash
gh api -X PUT repos/parterburn/dabble.me/pulls/<n>/merge -f merge_method=merge
```

Deploy status (`/me_ship` step 10). Railway posts one status per service on the merge commit.

```bash
gh api "repos/parterburn/dabble.me/commits/<merge-sha>/status" --jq '.statuses[] | select(.context | startswith("Dabble Me - dabble")) | [.context, .state] | @tsv'
```
