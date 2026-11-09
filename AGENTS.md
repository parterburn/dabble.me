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

### Sidekiq-Cron

Schedule file: `config/sidekiq_cron_schedule.yml`. With `SIDEKIQ_CRON_ENABLED` set, `config/initializers/sidekiq.rb` follows the [sidekiq-cron](https://github.com/sidekiq-cron/sidekiq-cron) pattern: `require "sidekiq/cron"` + `Sidekiq::Cron.configure { ... }`. The gem’s **ScheduleLoader** loads that YAML when each **Sidekiq** process starts.

| Variable | Purpose |
|----------|---------|
| `SIDEKIQ_CRON_ENABLED` | Set on worker environments so Sidekiq registers cron + loads the schedule at boot. Omit locally unless you want cron in dev. |

If Redis loses cron keys while Sidekiq stays up, reload from disk without restarting Sidekiq: **`bundle exec rake sidekiq_cron:reload`** (same semantics as boot: `load_from_hash!` / `load_from_array!` with `source: "schedule"`). On **Railway**, add a **Cron** service every 15 minutes with that command (same env vars / Redis URL as the web app). The rake task retries transient Redis connect timeouts (common on private-network cold starts).

### iOS app

SwiftUI app in `ios/` (see `ios/README.md`). Generate the project with `cd ios && xcodegen generate`; `DabbleMe.xcodeproj` is gitignored. It talks to `/api/v1` (`app/controllers/api/v1/`) with Doorkeeper tokens from the first-party `MobileApp` client, which `db:migrate` / `db:seed` register. The API specs are in `spec/requests/api_v1_spec.rb`.
