# AGENTS.md

## Cursor Cloud specific instructions

### Product overview

Dabble Me is a private journaling-over-email Rails 6.1 application. Users receive email prompts and reply to create journal entries. See `README.md` for full feature list.

### Tech stack

- Ruby 3.4.8 (managed via rbenv), Rails 6.1, PostgreSQL, Redis, Sidekiq, Puma
- Node.js 22.x only for Tailwind CSS marketing page build (`npm run build:css`)
- Tests: RSpec with Capybara + headless Chrome

### Services required

| Service | For tests | For dev server |
|---------|-----------|----------------|
| PostgreSQL | Required | Required |
| Redis | Not needed (inline adapter) | Required (Sidekiq) |
| Sidekiq | Not needed | Required for async jobs |

### Starting services

```bash
sudo service postgresql start
sudo service redis-server start
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
