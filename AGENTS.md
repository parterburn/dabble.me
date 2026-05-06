# AGENTS.md

## Cursor Cloud specific instructions

### Product overview

Dabble Me is a private journaling-over-email Rails 6.1 application. Users receive email prompts and reply to create journal entries. See `README.md` for full feature list.

### Tech stack

- Ruby 3.4.8 and Node.js 22.x (managed via asdf), Rails 6.1, PostgreSQL, Redis, Sidekiq, Puma
- Sidekiq is pinned to **7.3.x** (`Gemfile`): Sidekiq **8+** needs **Rack 3.2+** (Rails 7+). **sidekiq-cron** is **2.4.x** (current release line).
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
sudo pg_ctlcluster 16 main start
redis-server --daemonize yes
```

### Running the dev server

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

### Sidekiq-Cron

Schedule file: `config/sidekiq_cron_schedule.yml`. With `SIDEKIQ_CRON_ENABLED` set, `config/initializers/sidekiq.rb` follows the [sidekiq-cron](https://github.com/sidekiq-cron/sidekiq-cron) pattern: `require "sidekiq/cron"` + `Sidekiq::Cron.configure { ... }`. The gem’s **ScheduleLoader** loads that YAML when each **Sidekiq** process starts.

| Variable | Purpose |
|----------|---------|
| `SIDEKIQ_CRON_ENABLED` | Set on worker environments so Sidekiq registers cron + loads the schedule at boot. Omit locally unless you want cron in dev. |

If Redis loses cron keys while Sidekiq stays up, reload from disk without restarting Sidekiq: **`bundle exec rake sidekiq_cron:reload`** (same semantics as boot: `load_from_hash!` / `load_from_array!` with `source: "schedule"`). On **Railway**, add a **Cron** service every 10 minutes with that command (same env vars / Redis URL as the web app).
