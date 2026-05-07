# Dabble Me — Project Intent

> A note for any agent (human or AI) reading this code: this document captures the *why* behind the codebase. The README explains what it does and how to set it up; this doc explains the underlying intent so you can make changes that stay aligned with the original goals.

---

## 1. Core idea

**Dabble Me is a private journal that lives in your email inbox.**

The defining bet is that *people will journal more often if they don't have to remember to open another app*. Email is the lowest-friction surface that almost every adult on the internet already checks daily. So the product:

1. Sends you a "How was your day?" email on a schedule **you** pick (specific weekdays + a specific hour, in your local time zone).
2. Lets you simply **reply to that email** — and the reply body becomes your journal entry, complete with image attachments.
3. Surfaces a **random past entry** at the bottom of every prompt email, so each new entry is also a chance to re-encounter your own history.

Everything else in the codebase is in service of those three loops.

## 2. Original motivating context

Dabble Me was built as a **direct replacement for OhLife** — a much-loved email-based journaling service that shut down. The product still treats this as a load-bearing audience:

- There's a dedicated `OhLife` import flow ([entries/import/ohlife](app/controllers/import_controller.rb)) including image-archive upload.
- There's an SEO landing page at `/ohlife-alternative` ([welcome_controller.rb](app/controllers/welcome_controller.rb)).
- Imported entries are tagged with `Inspiration.category = "OhLife"` so they're identifiable forever.

If you're modifying behavior around imports, scheduling, or the email reply format, **do not break OhLife parity unless explicitly asked** — that audience is part of the product's reason for existing.

## 3. Product surface area (and what each piece is for)

| Surface | Purpose / intent |
|---|---|
| **Hourly cron + per-user schedule** ([SendHourlyEntriesWorker](app/workers/send_hourly_entries_worker.rb)) | The single most important job in the system. If this misses a run, users don't get their journal prompt. It's the *only* job wired up to Sentry cron monitoring (the Sentry plan only allows one monitor — that's the one). |
| **Email reply ingestion** (Mailgun → `email_processor` → Griddler) | The primary way entries are created. Reply-to-post must keep working; web compose is secondary. |
| **Web app** (`/entries`, `/write`, `/search`, `/review/:year`) | For browsing, searching, and the more involved features (Year in Review, calendar, songs view). Treat the web UI as a companion to email, not the primary surface. |
| **AI Assistant ("DabbleMeGPT")** ([Entry::AiAssistant](app/models/concerns/entry/ai_assistant.rb), [AiEntryJob](app/jobs/ai_entry_job.rb)) | **PRO-only, closed beta.** No UI to opt in — a handful of "super friendlies" are flagged on manually. The intent is a low-key journaling partner, not a chatbot. Treat the gating as deliberate; do not add a self-serve opt-in unless asked. |
| **Auto-tagging / sentiment** ([AiTaggingJob](app/jobs/ai_tagging_job.rb), `entries.sentiment` jsonb column) | Same PRO-only beta cohort as DabbleMeGPT. Quietly enriches entries so search and "emotion" filtering work without manual tagging. |
| **Hashtag support** | User-driven tagging for entries they want to find later. |
| **Spotify songs** | Entries can carry a list of songs; the UI embeds Spotify players. Adds a "what was I listening to" dimension to memory. |
| **Image upload (S3 + CloudFront + libvips/libheif)** | One image per entry. HEIC/HEIF is explicitly supported because that's what iPhones produce by default. Conversion happens async via [ProcessEntryImageJob](app/jobs/process_entry_image_job.rb) with a placeholder image while it works. |
| **MCP server** (`/mcp`, [McpController](app/controllers/mcp_controller.rb), [Mcp::DabbleServer](app/services/mcp/)) | Lets PRO users connect Dabble Me to AI clients (Claude, etc.) over OAuth so the assistant can search/list/analyze/create entries. **Currently a power-user feature**, but the medium-term bet is getting listed in the OpenAI / Claude connector stores so non-technical users can one-click install. Decisions about MCP UX, naming, scope descriptions, and OAuth flow should be made with that future audience in mind, not just current power users. |
| **X (Twitter) bookmark digests** ([XBookmark](app/models/x_bookmark.rb), [XBookmarkSummariesWorker](app/workers/x_bookmark_summaries_worker.rb)) | **Paul-only feature** that lives in this app to avoid spinning up (and paying for) a separate Railway service. Not exposed to other users. If a refactor would meaningfully simplify the rest of the codebase by extracting it, that's worth flagging — but don't extract unprompted. |
| **Admin portal** (`/admin/*`, Sidekiq UI at `/sidekiq`) | Operator-only views: user counts, payments/MRR, photos, Sidekiq state. Gated by `User#admin?`. |
| **Year in Review** (`/review/:year`) | Always-on, surfaced in the navbar under stats. Pushed harder in marketing/email around end-of-year and start-of-year. The intent is "annual reflection ritual" — the EOY/BOY push is a campaign on top of an evergreen feature. |

## 4. Business model & plan tiers

- **Free** users get journaling with restricted email frequency.
- **PRO** users (Stripe Monthly/Yearly, plus legacy Forever via PayPal/Gumroad/Payhere) get the full feature set, including:
  - Unlimited daily emails
  - **MCP access** (PRO-only and additionally gated behind passkey or 2FA — see `Oauth::*` controllers and the `/security` page)
  - AI features
- Downgrades are real: [`User#revoke_doorkeeper_oauth_if_downgraded_from_pro`](app/models/user.rb) revokes MCP access when someone leaves PRO, and [UserDowngradeExpiredWorker](app/workers/user_downgrade_expired_worker.rb) handles plan expiry daily.

Stripe is the primary path; PayPal/Gumroad/Payhere are kept for **historical** users who paid years ago and should not lose access. Don't remove that legacy code unless those users have been migrated.

## 5. Implicit design principles I've inferred

These aren't written down anywhere but the code clearly reflects them.

1. **Email is the contract.** The schedule, the reply-to-post format, and the prompt subject line are user-visible surfaces. Changes here ripple to every user's inbox — treat them with the same care as a public API.
2. **Privacy first.** It's a *private* journal. There is no social graph, no sharing, no public entries. Don't add features that weaken that posture.
3. **Resilience over throughput.** [SendHourlyEntriesWorker](app/workers/send_hourly_entries_worker.rb) explicitly swallows per-user errors so one bad user doesn't break everyone else's prompt. The "uploading image" placeholder has a 30-minute timeout so a crashed worker can't permanently break an entry's UI. The system is biased toward "keep working for the other users" over "fail loudly."
4. **Solo-operator friendly.** One Sentry cron monitor (matches the plan limit). Sidekiq-Cron instead of an external scheduler. Free-tier-friendly third-party services listed in the README. The architecture assumes a single maintainer on a small budget.
5. **Years of data matter.** The earliest migration is from 2014. Users have over a decade of entries. Migrations and model changes need to assume that history is precious and irreplaceable.
6. **Don't over-modernize.** Rails 6.1 / Sidekiq 7.3 / sidekiq-cron 2.4 are pinned deliberately ([AGENTS.md](AGENTS.md)) — Sidekiq 8 would force a Rails 7 upgrade. Don't bump major versions casually.

## 6. Things that look weird but are intentional

- **Sidekiq pinned to 7.3.x.** See above. Don't "upgrade" without a Rails 7 plan.
- **Rubocop config exists but rubocop is not in the Gemfile.** Not part of the workflow ([AGENTS.md](AGENTS.md)).
- **Hourly worker's cron schedule is duplicated** in both [config/sidekiq_cron_schedule.yml](config/sidekiq_cron_schedule.yml) and [the worker file itself](app/workers/send_hourly_entries_worker.rb) (for Sentry monitor registration). Keep them in sync.
- **`Inspiration` row with category "OhLife"** is load-bearing for the OhLife importer — it's the FK target for imported entries.
- **Body field stores HTML, including embedded `<div data-content='dabblemegpt'>` AI responses.** The DOM-ish markers are how AI replies are detected and re-rendered. Don't strip them.
- **Default S3 image domain in the model is a CloudFront URL** (`d10r8m94hrfowu.cloudfront.net`). That's a real prod CDN — don't accidentally hardcode it elsewhere.

## 7. Hosting & operational context

- **Production runs on Railway.** Heroku is dead — the `Procfile`, `Aptfile`, and other Heroku-flavored bits are still present but only because they happen to also work on Railway / are lightweight to keep. Don't introduce Heroku-specific assumptions.
- **No external scheduler.** Sidekiq-Cron inside the Sidekiq worker is the source of truth. A separate Railway "Cron" service exists only as a fallback to reload schedules if Redis loses cron keys (see [AGENTS.md](AGENTS.md)).

## 8. Current product mode

**Active growth, not maintenance.**

A big marketing-page refresh just landed and Paul is hoping for growth. Competition is getting stronger because home-built journaling-with-AI is increasingly viable for technical users, so Dabble Me's edge is the *zero-friction email loop* + *years of trustworthy history* + *one-click connector install* (once the connector-store path lands).

Implications for agents:

- Marketing page (`app/views/welcome/*`, `public/marketing.css`) is a live surface that just got polished — don't degrade it.
- Performance, deliverability, and onboarding friction matter more than they would in pure maintenance mode.
- Proposing growth-relevant improvements (conversion, SEO, onboarding clarity, MCP store readiness) is welcome; proposing speculative architectural rewrites is not.

## 9. Things to be careful around

These are the bits Paul would be upset to discover an agent had quietly broken — codifying them so future agents don't have to guess:

- **The hourly send loop.** [SendHourlyEntriesWorker](app/workers/send_hourly_entries_worker.rb) is the heart of the product. It must keep running, keep its Sentry monitor in sync with the cron schedule, and keep swallowing per-user errors.
- **Email reply ingestion.** Mailgun → `email_processor` → Griddler → `Entry`. Every paying user depends on this round-trip working.
- **Per-user data integrity.** Entries go back to 2014 for some users. Any migration touching `entries`, `users`, or `hashtags` should be additive and reversible by default.
- **OhLife import compatibility.** That audience is part of why the product exists.
- **PRO downgrade flow.** OAuth/MCP access must be revoked when a user leaves PRO ([User#revoke_doorkeeper_oauth_if_downgraded_from_pro](app/models/user.rb), [UserDowngradeExpiredWorker](app/workers/user_downgrade_expired_worker.rb)).
- **Legacy payment paths (PayPal / Gumroad / Payhere).** Don't strip them — there are still "Forever" plan users from those eras.
- **The marketing page.** Just refreshed; treat as a live, load-bearing growth surface.
- **MCP scopes, OAuth metadata, and tool descriptions.** These will be read by the OpenAI/Claude connector stores' review processes. Sloppy scope names or vague tool docs could block listing.
