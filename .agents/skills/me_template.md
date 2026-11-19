# PR Format Template

This file is the single source of truth for PR description format. Assume the human reads **only the PR description**. Order:

1. **Flags for human review** (always first)
2. The general description (below)
3. **Artifacts** (last)

## 1. Flags for human review

An easy-to-scan bulleted list, one line each, of everything the human should check or watch out for. Write `None` only if truly empty. Include when they apply:

- Decisions, assumptions, and deviations from the request
- Risks (migrations, data changes, auth, encryption, performance)
- `/me_review` findings and human review comments that were skipped or declined, with the reason
- A local check that could not run (`local verification unavailable (<reason>)`)
- Flaky-test reruns (job name and why it is a suspected transient failure)
- Post-deploy steps a person still has to do
- Blockers, e.g. merge permission denied or checks still pending

Refresh the list whenever the PR changes; keep human edits to it.

## 2. General description

Write from the perspective of someone who uses Dabble Me. Include:

- A high-level summary (1-2 sentences) explaining what this PR does
- A bulleted list of practical changes: what a writer, or an admin, will see or experience differently. Use clear language. Keep implementation detail in a short technical note only when a reviewer needs it.

**Example**:
Drafts keep their photos when you leave the editor and come back.

- Save Draft stores the photos with the words
- Starting a new entry restores that draft, photos in the same order
- Cancel no longer offers a separate "Words Only" choice

**Post-deploy follow-ups** (optional, only when this PR leaves work a person must do after deploy):

- A checklist of concrete steps, with how to verify. Never list `bin/rails db:migrate`; `bin/release` runs it. Don't put journal text, names, or email addresses in the list.

## 3. Artifacts

Include screenshots or videos already produced while doing the work, last in the description. Don't open a browser or record anything just to fill this section. Embed with `<img src="/opt/cursor/artifacts/x.png" />` or `<video src="/opt/cursor/artifacts/x.mp4" controls></video>` (absolute paths under `/opt/cursor/artifacts`). Confirm each file exists before embedding. Omit the section when there are none.
