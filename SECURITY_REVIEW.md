# Security & Privacy Review — Dabble Me

_Reviewed: 2026-07-15. Scope: authentication (login, passkeys, OTP), sessions/transport,
authorization & data access (web, OAuth/MCP, webhooks, inbound email), and privacy posture._

This document records the findings of a security review. Two clear-cut SQL injection
issues were fixed directly on this branch (see **Fixed in this branch** below). Everything
else is written up as a prioritized recommendation because it involves a product decision,
an operational change, or configuration outside the codebase.

---

## Summary

The app gets a lot right: OAuth for MCP forces PKCE (S256) and hashes tokens/secrets,
the MCP image-fetch path has a thorough SSRF guard, Sentry payloads run through a
credential scrubber, Rack::Attack throttles logins/OAuth/MCP, passkey registration
requires password re-authentication and emails the user, account deletion has a 1-hour
grace window and revokes OAuth tokens, and cookies are `secure` + `SameSite=Lax` with
`force_ssl`/HSTS on in production.

The most important issues were **two SQL injection sinks in `EntriesController`**, both
reachable by any logged-in user. These have been fixed. The remaining items are ranked
below.

---

## Fixed in this branch

### 1. SQL injection in `EntriesController#review` (High)
`app/controllers/entries_controller.rb`

`@year` came straight from `params[:year]` (route `/review/:year` or query string) and was
interpolated into raw SQL:

```ruby
@year = params[:year] || ...
current_user.entries.where("date >= '#{@year}-01-01'::DATE AND date <= '#{@year}-12-31'::DATE")
# and, when the user has >20 entries, across ALL users:
Entry.where("date >= '#{@year}-01-01'::DATE AND date <= '#{@year}-12-31'::DATE").group(:user_id)...
```

The second query is **not scoped to the current user** (`Entry.where`), so a crafted
`year` value enabled cross-tenant data inference. Any authenticated (even free) user with
21+ entries could reach it.

**Fix:** validate `year` against `/\A(19|20)\d{2}\z/`, coerce to an integer, and use a
Ruby `Date` range with ActiveRecord bind parameters. Invalid input now raises the existing
`InvalidDateError`.

### 2. SQL injection in `EntriesController#index` JSON calendar (High)
`app/controllers/entries_controller.rb`

The FullCalendar JSON endpoint interpolated `params[:start]` / `params[:end]` directly:

```ruby
start_date = params[:start].presence || ...
end_date   = params[:end].presence || ...
current_user.entries.where("date >= '#{start_date}'::DATE AND date < '#{end_date}'::DATE")
```

Scoped to `current_user.entries`, but still an injectable sink (boolean/error/time-based
extraction).

**Fix:** parse the params with a new `parse_iso_date` helper (`Date.iso8601`, returns `nil`
on bad input) and pass them as bind parameters (`where("date >= ? AND date < ?", ...)`).

> Note: the `params[:subgroup]` interpolation on the month-view branch is guarded by a
> preceding `=~ /^\d+$/` check and is not injectable. Left as-is.

---

## Recommendations (not changed — need a decision or ops work)

### 3. Inbound-email entries trust a spoofable `From` (Medium)
`app/lib/email_processor.rb`, `config/initializers/griddler.rb`

`find_user_from_user_key` matches the sender to a user by **either** the secret
per-user address token **or** the raw `From` email:

```ruby
User.where(user_key: to_token).or(User.where(email: from_email)).first
```

`From` is trivially spoofable. Combined with the fact that the Mailgun inbound webhook
(`POST /email_processor` → griddler-mailgun) is **not signature-verified**, anyone who can
reach the endpoint can inject journal entries into a victim's account by forging the sender
(or by knowing/guessing routing). Impact is content injection / journal pollution, not
data exfiltration.

**Recommendation:** (a) verify the Mailgun webhook signature (`timestamp`/`token`/
`signature` HMAC with the Mailgun signing key) before processing — reject unsigned/invalid
posts; (b) treat the `user_key` token as the sole account selector, and only use `From`
as a secondary confirmation (e.g. require it to match the resolved user), not as an
independent match.

### 4. Uploads written into `public/` with a client-supplied filename (Medium)
`app/controllers/import_controller.rb`

Trailmix/OhLife imports move uploaded files into a web-served directory using the
attacker-controlled original filename:

```ruby
dir  = FileUtils.mkdir_p("public/trailmix_zips/#{current_user.user_key}")
file = File.join(dir, tmp.original_filename)
FileUtils.mv tmp.tempfile.path, file
```

Risks: files served from the app's own origin (an uploaded `.html`/`.svg` becomes
same-origin content → stored XSS if `RAILS_SERVE_STATIC_FILES` is on), private journal
archives left world-readable under a path keyed only by `user_key`, and reliance on Rack
sanitizing the filename to prevent traversal. PRO-gated, but still user-reachable.

**Recommendation:** store imports outside `public/` (a non-served tmp dir or S3), generate
a server-side random filename, validate content type, and delete after the import job runs.
Only `.zip`/`.json` should be accepted, and never served back inline.

### 5. MCP passkey/2FA requirement is currently disabled (Medium)
`app/lib/mcp/tools/helpers.rb`

```ruby
# TODO: restore `&& user.mcp_security_requirements_met?` after Claude/ChatGPT connector review.
return nil if user.is_pro? && !user.deletion_pending?
```

The security page and passkey-removal logic (`revoke_doorkeeper_access_tokens!` when
`mcp_security_requirements_met?` is false) assume MCP access requires a passkey or OTP.
That gate is commented out, so MCP journal read/write access currently requires **only**
a PRO plan. This weakens the documented posture for a full data-access API.

**Recommendation:** restore the `&& user.mcp_security_requirements_met?` check once the
connector flow is confirmed, or explicitly document that PRO alone authorizes MCP.

### 6. PayPal / Gumroad payment webhooks are not cryptographically verified (Medium)
`app/controllers/payments_controller.rb`

`payment_notify` verifies **PayHere** with an HMAC signature (good), but the PayPal and
Gumroad branches authenticate only by matching `seller_id`/`product_id`/`receiver_id` and
`payment_status` values present in the request body. A forged POST that includes the right
(non-secret or leakable) IDs can grant a PRO plan.

**Recommendation:** verify Gumroad's ping/`sale_id` via their API and PayPal IPN via the
postback verification flow (or migrate fully to Stripe webhooks with signature checking,
which the app already supports via `stripe_event`).

### 7. No Content Security Policy (Low/Medium)
`config/initializers/content_security_policy.rb` (entirely commented out)

Entry bodies are authored via Summernote (rich HTML) and rendered with `html_safe` in
several places. Server-side sanitization is the primary defense, but there is no CSP to
contain a sanitizer bypass or a third-party script issue.

**Recommendation:** add a CSP (start in `Report-Only`), restricting `script-src`/`object-src`
and allow-listing the embeds actually used (Spotify iframes, Cloudflare Turnstile, CDN).

### 8. Password policy is weak; `devise-security` installed but unconfigured (Low)
`config/initializers/devise.rb`, `config/initializers/devise-security.rb`

Minimum password length is 6 and no complexity/breach/rotation checks are enabled (the
`devise-security` initializer is all comments).

**Recommendation:** raise the minimum to at least 8–10, and consider a HaveIBeenPwned
breach check on sign-up/reset. Account lockout is reasonably covered by Rack::Attack
login throttles, so `:lockable` is optional.

### 9. Private journal content sent to Sentry on errors (Low — privacy)
`app/lib/email_processor.rb`, `app/controllers/application_controller.rb`

The Sentry scrubber (`lib/sentry_sensitive_scrubber.rb`) reliably removes credentials and
tokens, but error captures deliberately include entry `body` / `raw_body` / `html` and full
request params. That means private journal text can flow to Sentry for debugging.

**Recommendation:** confirm this is acceptable under the privacy policy, or truncate/redact
entry bodies in those `extra` payloads. (Low urgency — it's diagnostic data, not credentials.)

### 10. User/passkey enumeration (Low)
`app/controllers/passkeys/sessions_controller.rb`

`Passkeys::Sessions#new` returns `404 {"errors":["User not found"]}` for unknown emails vs a
challenge for known ones, allowing account enumeration. Login/reset flows can leak the same
signal via timing/messages.

**Recommendation:** return a uniform response regardless of whether the email exists (the
existing Rack::Attack `req/ip` throttle limits brute-forcing but doesn't remove the oracle).

### 11. SSRF fetch has a DNS-rebinding TOCTOU window (Low)
`app/services/mcp/entry_creator.rb`

`safe_fetch_host?` resolves and validates the host, then `Net::HTTP.new(uri.host, ...)`
re-resolves at connect time — a classic rebinding gap. The guard is otherwise strong
(blocks loopback/private/link-local/ULA, no embedded creds, https-only in prod, redirect
re-checks), and the endpoint is PRO-gated.

**Recommendation:** pin the validated IP for the actual connection (connect to the resolved
address with the original host header/SNI) to close the window.

---

## Dependency vulnerabilities

GitHub Dependabot reports 26 alerts on the default branch. Running `bundler-audit`
(ruby-advisory-db) against `Gemfile.lock` surfaces **31 advisories** (the DB is a superset
of Dependabot). The important nuance is **reachability**: several map to Rails subsystems or
Devise modules this app does not load, so the real exposure is much smaller than the raw count.

> The lockfile could not be regenerated in this review environment (Ruby 3.4.10 required by
> the Gemfile is not installed here — only up to 3.3.6), so the bumps below are a plan to run
> locally with `bundle update`, not applied changes.

### A. Not reachable in this app (12 of 31) — safe to deprioritize
- **activestorage (6 advisories)** — `config/application.rb` requires railties individually
  and never loads `active_storage/engine`. Active Storage is not in the app; DiskService path
  traversal / glob injection / proxy-mode DoS / content-type bypass do not apply.
- **puma (2, both rated High)** — both are PROXY-protocol-v1 parser bugs. The app has no
  `proxy_protocol` binding (no custom `bind` in `config/puma.rb`), so the vulnerable parser
  is never enabled.
- **net-imap (3)** — command injection / DoS via IMAP commands. The app sends mail via the
  Mailgun API and receives via Griddler webhooks; it never opens IMAP connections.
- **devise (1 of 2)** — the "change email confirmable race" requires `:confirmable`, which the
  `User` model does not enable.

  A bump is still worthwhile as defense-in-depth, but none of these is an active hole today.

### B. Also not applicable, worth noting
- **devise — Timeoutable open redirect (`CVE-2026-40295`)** — requires `:timeoutable`; the
  `User` model does not use it. Not applicable.

### C. Reachable / act on these
Direct dependency, in-constraint, low-risk:
- **carrierwave 3.1.2 → 3.1.3** (Medium, `~> 3` already allows it). Content-type **denylist**
  bypass. This app uses an **allowlist** (`file_content_type allow: ALLOWED_IMAGE_TYPES`), so
  likely not exploitable here, but the bump is trivial — do it.

Transitive, fixable via `bundle update` (subject to parent-gem constraints):
- **faraday 2.14.2 → 2.14.3** (High) — NestedParamsEncoder recursion DoS. Pulled in by
  `ruby-openai` (and others). Patch bump.
- **jwt 3.1.2 → 3.2.0** (High) — empty-key HMAC bypass. Transitive. Patch/minor bump.
- **json 2.19.5 → 2.19.9** (Low) — heap overflow when streaming to IO.
- **websocket-driver 0.8.0 → 0.8.2** (4 advisories) — header/compression memory-exhaustion DoS.
- **net-imap → 0.6.4.1** — bump anyway (see A; not reachable but cheap).
- **excon 0.91.0 → 1.5.0** (Medium) — header redaction on redirect. **Caveat:** `excon` is
  held at 0.91 by `fog-aws`/`fog-core`, which may cap `excon < 1.0`. Bumping likely requires
  updating the `fog-*` stack too; verify the resolve before committing.

Suggested command (run locally on Ruby 3.4.10, then run the suite):
```
bundle update carrierwave faraday jwt json websocket-driver net-imap
# excon: attempt separately; may require fog-aws/fog-core updates
```

### D. Needs a decision — `concurrent-ruby` and the Rails 6.1 EOL
- **concurrent-ruby 1.3.4 → 1.3.7** (3 advisories: lock-correctness bugs). This gem is
  **pinned at 1.3.4** in the `Gemfile` with a comment about a Rails PR. The pin exists because
  newer `concurrent-ruby` dropped its internal `logger` require, which breaks Rails 6.1 boot.
  To bump safely, add `gem "logger"` explicitly (or upgrade Rails) and then move the pin to
  `>= 1.3.7`. **Test app boot** after this change — it's a known 6.1 compatibility landmine.

- **Rails core — actionpack, actionview, activerecord, activesupport (5 reachable advisories)**
  — CSP bypass in Action Dispatch, XSS in Action View tag helpers, ANSI-escape injection in
  AR logging, ReDoS/XSS/DoS in Active Support number & `SafeBuffer#%` helpers. Every fix
  requires **Rails ≥ 7.0.8.7 / 7.1 / 7.2 / 8.0**. The app is on **Rails 6.1.7.10, which is
  end-of-life and receives no further security patches** — this is the root cause of most of
  the Rails-family alerts and the single most important dependency item.

  **Recommendation:** plan a Rails 7.x upgrade (7.1 or 7.2 LTS-ish line). It's a multi-day
  effort (Zeitwerk already on, but check `bundle update` for devise/doorkeeper/carrierwave
  compatibility). Until then, individual 6.1 CVEs cannot be patched by gem bumps. Reachability
  of the specific advisories is low-to-moderate given current usage (no CSP set yet, limited
  number-helper exposure), but the EOL status alone is the reason to prioritize the upgrade.

### Priority order
1. **Plan the Rails 6.1 → 7.x upgrade** (EOL framework; unlocks ~5 core CVEs).
2. **Patch bumps now:** carrierwave, faraday (High), jwt (High), json, websocket-driver, net-imap.
3. **concurrent-ruby** bump alongside an explicit `logger` gem (test boot).
4. **excon** — only with a coordinated `fog-*` update.
5. Enable **Dependabot security updates** (auto-PRs) so transitive patch bumps land continuously.

---

## Things that are done well (no action needed)

- **OAuth/MCP:** `force_pkce` + `pkce_code_challenge_methods ['S256']`, `hash_token_secrets`,
  `hash_application_secrets`, scoped tokens, `force_ssl_in_redirect_uri`, dynamic client
  registration rate-limited (per-minute and per-day).
- **MCP tenancy:** the journal owner is always loaded from server context (`scoped_user!`),
  never from tool arguments; presigned upload keys are validated against the account.
- **Transport/session:** `force_ssl` + HSTS in production, `secure`/`SameSite=Lax` session
  and remember cookies, remember-me tokens invalidated on sign-out.
- **Rate limiting:** Rack::Attack throttles general traffic, login (per-IP and per-email),
  MCP, and OAuth token/registration abuse.
- **Passkey lifecycle:** registration requires current password + emails the user; removing
  the last credential revokes MCP tokens when 2FA requirements are no longer met.
- **Account deletion:** soft-delete with a 1-hour cancellable grace window and OAuth token
  revocation on downgrade.
- **Secrets hygiene:** Sentry scrubber filters `password`/`token`/`secret`/`otp` keys and
  bearer/`access_token` strings from events, breadcrumbs, and request data.
