# AGENTS.md

## Cursor Cloud specific instructions

### Product overview

Dabble Me is a private journaling-over-email Rails 8.1 application. Users receive email prompts and reply to create journal entries. See `README.md` for full feature list.

### Tech stack

- Ruby 4.0.9 and Node.js 22.x (managed via asdf), Rails 8.1, PostgreSQL, Redis, Sidekiq, Puma
- Sidekiq **8.1.x** on Rack **3.2.x** with connection_pool **3.x** (`Gemfile`). Sidekiq 8 needs Redis **7+** (Railway runs Redis 8). **sidekiq-cron** is **2.4.x** (current release line).
- Tests: RSpec with Capybara + headless Chrome

### Shell initialization

New shells must load asdf before running Ruby/Node commands:

```bash
. "$HOME/.asdf/asdf.sh"
```

Or ensure `~/.bashrc` sources it.

### Services required

| Service | For tests | For dev server |
|---------|-----------|----------------|
| PostgreSQL | Required | Required |
| Redis | Not needed (inline adapter) | Required (Sidekiq) |
| Sidekiq | Not needed | Required for async jobs |

### Starting services

```bash
sudo pg_ctlcluster 18 main start
redis-server --daemonize yes
```

`config/database.yml` sets no DB username, so the app connects to Postgres via peer auth as the OS user `ubuntu`. If a fresh cluster errors with `role "ubuntu" does not exist`, create it once:

```bash
sudo -u postgres psql -c "CREATE ROLE ubuntu WITH LOGIN SUPERUSER;"
```

Then create/seed the dev DB with the dev env vars: `bundle exec rails db:create db:schema:load db:seed`.

### Running the dev server

Development and test load a gitignored `.env` via `dotenv-rails` (see `.env.example`). A 1Password Environments mount at `.env` is the expected local source. Variables already set in the shell win over `.env`.

```bash
mkdir -p tmp/pids
MAIN_DOMAIN=localhost SECRET_KEY_BASE=dev_secret_key_base_1234567890 DEVISE_SECRET_KEY=dev_devise_secret_1234567890 bundle exec puma -p 3000 -C config/puma.rb
```

The seed admin account is `admin@dabble.ex` / `dabble` (created by `rake db:seed`).

### Running tests

Tests require several environment variables (see `.github/workflows/test.yml`):

```bash
MAIN_DOMAIN=test DEVISE_SECRET_KEY=test SMTP_DOMAIN=test AWS_ACCESS_KEY_ID=test AWS_BUCKET=test AWS_SECRET_ACCESS_KEY=test bundle exec rspec
```

Or simply `bundle exec rake` with the same env vars.

### Gotchas

- The `libheif1` .deb URL in `Aptfile` targets Debian and may have dependency conflicts on Ubuntu 24.04. Use the Ubuntu-packaged `libheif1` instead. The `libvips42t64` runtime package must be explicitly installed (the `-dev` package alone is insufficient).
- `tmp/pids/` directory must exist before starting Puma in cluster mode; create it with `mkdir -p tmp/pids`.
- `.rubocop.yml` exists but `rubocop` is not in the Gemfile — it is not part of the standard dev workflow.
- `npm run build:css` builds marketing page Tailwind CSS to `public/marketing.css`. Run it after `npm install`.
- `npm run build:css:app` builds `public/app-tailwind.css` for logged-in pages restyled with Tailwind (`watch:css:app` while editing). The output is committed, and CI fails if it is stale, so rebuild and commit it after changing a restyled view or `app/frontend/stylesheets/app.tailwind.css`.
  - A page opts in with `<% content_for :tailwind, true %>` and a `<div class="tw …">` wrapper (see `devise/registrations/edit.html.erb`). Add the view to the `@source` list in `app.tailwind.css`; Tailwind scans nothing else.
  - Utilities are `!important` so they beat the legacy `ui.scss` styles. Don't reuse a Tailwind utility name (`flex`, `hidden`, `container`…) as a legacy class in the shared layout; `spec/lib/app_tailwind_css_spec.rb` checks the navbar and footer.
  - Shared pieces: `card`, `field-*`, `button-*` and `data-table` (in `app.tailwind.css`); `paginate records, theme: "tw"` (`app/views/kaminari/tw/`); and for admin pages, `admin/_header` (title and section tabs) and `admin/_section` (a titled card around a table).

### Sidekiq-Cron

Schedule file: `config/sidekiq_cron_schedule.yml`. With `SIDEKIQ_CRON_ENABLED` set, `config/initializers/sidekiq.rb` follows the [sidekiq-cron](https://github.com/sidekiq-cron/sidekiq-cron) pattern: `require "sidekiq/cron"` + `Sidekiq::Cron.configure { ... }`. The gem’s **ScheduleLoader** loads that YAML when each **Sidekiq** process starts.

| Variable | Purpose |
|----------|---------|
| `SIDEKIQ_CRON_ENABLED` | Set on worker environments so Sidekiq registers cron + loads the schedule at boot. Omit locally unless you want cron in dev. |

If Redis loses cron keys while Sidekiq stays up, reload from disk without restarting Sidekiq: **`bundle exec rake sidekiq_cron:reload`** (same semantics as boot: `load_from_hash!` / `load_from_array!` with `source: "schedule"`). On **Railway**, add a **Cron** service every 15 minutes with that command (same env vars / Redis URL as the web app). The rake task retries transient Redis connect timeouts (common on private-network cold starts).

### Encryption at rest

Journal text and account secrets are encrypted with Active Record Encryption: `entries.body`, `original_email_body` and `original_email`; `users.user_key` and `image_key` (deterministic, so exact lookups work), `first_name`, `last_name`, `past_filter`, `otp_auth_secret` and `otp_recovery_secret`; `hashtags.tag`.

- Never read these columns in SQL (`LIKE`, regex, `ORDER BY`, `= ''`). Match entry text with `Entry::Matcher`; compare and sort the others in Ruby. `pluck` decrypts.
- Development and test use fixed, insecure fallback keys, so no setup is needed. Production needs the three key variables; `EncryptionCheck.verify!` stops a web or worker process that lacks them or holds different keys from the process that started first.
- In specs, `stored_value(record, column)` and `ciphertext?` (`spec/support/encryption_helpers.rb`) read what the database actually holds.

| Variable | Purpose |
|----------|---------|
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`, `_DETERMINISTIC_KEY`, `_KEY_DERIVATION_SALT` | The keys. Losing them loses every encrypted row; changing them does the same. |
| `ACTIVE_RECORD_ENCRYPTION_WRITE` | `true` writes ciphertext. Defaults to `false` in production and `true` elsewhere. Every process can read ciphertext either way (`Encryption::StagedEncryptor`, installed in `config/initializers/active_record_encryption.rb`). |
| `ACTIVE_RECORD_ENCRYPTION_ALLOW_PLAINTEXT` | `false` makes a plaintext row raise instead of reading. Set it only after `rake encryption:status` reports none left. |

Rake tasks (each takes `USER_ID=` for one account and `PAUSE=` seconds between batches): `encryption:status` counts plaintext rows, `encryption:rehearse` round-trips every value in memory without writing, `encryption:backfill` encrypts existing rows and verifies each one, `encryption:decrypt` (with `CONFIRM=decrypt`) is the way back.

### Admin access

Admin pages (`/admin/*` and `/sidekiq`) have two extra gates on top of `users.admin`. Doorkeeper's own client screens (`/oauth/applications`) are switched off; `/admin/oauth` lists OAuth clients instead, and `OauthAppCleanupWorker` deletes self-registered ones unused for 30 days.

- **Passkey every 12 hours.** An admin's session must confirm a passkey (`AdminAccess`, checked by `ApplicationController#require_admin_passkey` and by `AdminPasskeyGate` around Sidekiq), whichever way they signed in. Passkey sign-in counts; a password, a 2FA code or a remember-me cookie alone sends them to `/passkeys/verification/new`. An admin without a passkey can only add one, and can't remove their last. A locked-out admin is recovered from the Rails console.
- **Cloudflare Access.** With both variables set, those routes also need a valid Cloudflare Access token (`CloudflareAccess` checks the `Cf-Access-Jwt-Assertion` header against the team's signing keys); anything else gets a 404. Without them the check is off, as in development and test.

| Variable | Purpose |
|----------|---------|
| `CLOUDFLARE_ACCESS_TEAM_DOMAIN` | e.g. `dabble.cloudflareaccess.com` |
| `CLOUDFLARE_ACCESS_AUD` | The Access application's Application Audience (AUD) tag |

### Exports

`entries#export` with `.md` streams the journal as Markdown on the spot (`ExportMarkdown`). Any other request becomes an `Export`, for everything or for one year or search: `ExportEntriesJob` builds a ZIP with `ExportArchive` (`journal.html` from `ExportHtml`, `journal.md`, `entries.json`, `images/`), `ExportStore` uploads it privately, and `UserMailer.export_ready` emails a link. Asking for the same thing again within `Export::LIMIT_PERIOD` (12 hours) downloads the last export; `exports.scope` says what an export holds (`all`, `year:2021`, or `search:` with a keyed digest, never the search words). A person can start `Export::HOURLY_LIMIT` (10) exports an hour.

- The emailed link goes to `ExportsController`, which needs a sign-in and only shows an export to its owner. `download` redirects to a storage link that lasts `Export::LINK_LIFETIME`. Never attach an export to an email or link to its file directly.
- Exports are private: stored under `exports/` with no public ACL, in `AWS_EXPORTS_BUCKET` when set (`AWS_EXPORTS_REGION` if its region differs). Don't write them under `uploads/`, which is served publicly.
- They last `Export::LIFETIME` (7 days). `ExportCleanupWorker` (daily, in `config/sidekiq_cron_schedule.yml`) deletes expired files; a storage lifecycle rule on `exports/` should back it up.

### Newsletters

Letters to subscribers live in `newsletters/<name>/`: one Markdown `letter.md`, and a `newsletter.yml` naming its variants and who gets which (`newsletters/README.md` has the format). `Newsletter` (`app/lib/newsletter.rb`) loads them, `NewsletterMailer` sends one, and `NewsletterDeliveryJob` sends a person a newsletter at most once, recorded in `newsletter_deliveries`.

- `newsletter.yml` lists the audiences, `pro`, `free` or both. Everyone needs `users.send_updates` true ("Send me updates about Dabble Me" in email settings); journal prompts (`frequency`) are a separate setting. Free accounts must also have no bounces and, with `active_within_months`, a recent sign-in or entry. An audience can send from its own address and Mailgun domain.
- `rake 'newsletter:preview[name,email]'` emails every variant to one account. `rake 'newsletter:send[name]'` prints who would get what and sends only with `SEND=yes`; `PLAN=` limits it to one plan and `LIMIT=` to a number of emails. A send is refused while a letter contains `TODO` or `MAILING_ADDRESS` is unset.
- The unsubscribe link (`/updates/unsubscribe`, `EmailUpdatesController`) takes the same signed token as the settings links and accepts a one-click POST without CSRF.

### iOS app

SwiftUI app in `ios/` (see `ios/README.md`). Generate the project with `cd ios && xcodegen generate`; `DabbleMe.xcodeproj` is gitignored. It talks to `/api/v1` (`app/controllers/api/v1/`) with Doorkeeper tokens from the first-party `MobileApp` client, which `db:migrate` / `db:seed` register. The API specs are in `spec/requests/api_v1_spec.rb`.
