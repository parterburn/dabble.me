# Dabble Me
### A private journal over email service.

Dabble Me helps people remember what's happened in their life. Use it as a light-weight journal on a daily, weekly, or even monthly basis...it's up to you! Dabble Me will email you on a time & days you choose - you simply reply to the email to post entries. The app is live at [https://dabble.me](https://dabble.me). This is a great replacement if you had ever used [OhLife](http://ohlife.com).

This app utilizes the following 3rd party services:

* [CloudFlare](http://cloudflare.com) managed DNS + free SSL support (free for basic service)
* [Mailgun](http://www.mailgun.com/rackspace) for Sending & Receiving Email (free for 50k emails per month)
* [Amazon S3](http://aws.amazon.com) for Photo Uploads & Storage (free for 1 year)
* [Google Analytics](http://google.com/analytics) for traffic stats (free for standard analytics)
* [Turnstile](https://www.cloudflare.com/products/turnstile/) to prevent bot signups (free).
* [Sentry](https://www.sentry.io/) to report errors (free)

You will need to setup Mailgun to receive incoming emails and point them to your app to parse.

Scheduled jobs (including hourly email sending) are run by [sidekiq-cron](https://github.com/sidekiq-cron/sidekiq-cron) inside the Sidekiq worker process. The schedule lives in `config/schedule.yml`. No external scheduler is required.

Your local environment variables at ```config/local_env.yml``` (and on Railway) will need to be something like this (```rake db:seed``` will create the admin@dabble.ex account for you):

```yaml
MAIN_DOMAIN: yourdomain.com
SECRET_KEY_BASE: 1234..1234
DEVISE_SECRET_KEY: 1234..1234
SMTP_DOMAIN: post.yourdomain.com
MAILGUN_API_KEY=api-key
TURNSTILE_SITE_KEY: 6Lc6BAAAAAAAAChqRbQZcn_yyyyyyyyyyyyyyyyy
TURNSTILE_SECRET_KEY: 6Lc6BAAAAAAAAKN3DRm6VA_xxxxxxxxxxxxxxxxx
GOOGLE_ANALYTICS_ID=UA-12345-67 ## ONLY FOR PRODUCTION
SENTRY_DSN: https://dsn.sentry.io/1234
OPENAI_ACCESS_TOKEN: sk-1234
OPENAI_ORGANIZATION_ID: org-1234
HUGGING_FACE_API_KEY: 1234
STRIPE_API_KEY: sk_test_1234
STRIPE_SIGNING_SECRET: whsec_1234
```

### Things you may want to rip out

You can opt to not use Turnstile: simply don't add an environment variables for `TURNSTILE_SITE_KEY`.

### MCP (Model Context Protocol)

PRO accounts can use Dabble Me as a **remote MCP server** so compatible clients (for example Claude) can search, list, analyze, and create journal entries after OAuth.

**Requirements:** PRO subscription, plus a passkey or two-factor authentication on Account security (`/security`). Connected OAuth apps can be reviewed and revoked on the same page under **Connected apps** (shown only when something is connected).

**Endpoint:** Streamable HTTP at `https://<MAIN_DOMAIN>/mcp` (see `MAIN_DOMAIN` in `config/local_env.yml`). The client should use OAuth: authorization metadata is published under `/.well-known/oauth-authorization-server` and `/.well-known/oauth-protected-resource` (see `Oauth::MetadataController`).

**User-facing instructions:** [Support → MCP](https://dabble.me/support#mcp) (or `/support#mcp` on your own host).

**Deep links for assistants:** a single day opens at `https://<MAIN_DOMAIN>/entries/YYYY/M/D` with **unpadded** month and day (example: `https://dabble.me/entries/2026/4/21`). The web compose URL is `https://<MAIN_DOMAIN>/write`.

For generic remote-connector setup in Claude, see Anthropic’s [Get started with custom connectors using remote MCP](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp).

**Automated smoke (curl + [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) CLI):** `./script/mcp_inspector_smoke.sh` uses `RAILS_ENV=test`, starts a short-lived Rails server, checks OAuth metadata and `/mcp`, then runs Inspector against all four tools (`tools/list` exercises `initialize` + connect). Aligns with Anthropic’s [Testing your connector](https://claude.com/docs/connectors/build/testing) guidance.

### Tests

There is healthy coverage of the app, which you can run with:

```
rake
```

### Administration Portal

The Admin emails are accounts that have access to the Admin Dropdown in the navbar (lock icon) that give you details into the number of entries and users in the system.

### Inspirations and OhLife Importer

If you want random bits of inspiration, you can load up different quotes in the Inspiration table to be shown above the New Posts page and at the bottom of emails. If you plan on using OhLife, the system will tag imported posts with ```inspiration_id``` of 1 - so create the first Inspiration with a category name of "OhLife".

```ruby
Inspiration.create(category: 'OhLife', body: 'Imported from OhLife')
```

=====

**Current features:**

* Read past entries by month/year
* Create new entries with simple formatting
* OhLife Importer
* Email: Reply-to-post new entries on days of the week you choose (with random past entries embedded)
* Associate 1 image to a specific entry
* Search with basic analytics around posting
* Hashtag support for tagging your entries
* Year in Review
* MCP (PRO): OAuth-backed journal tools for external clients
