# Security Policy

## Reporting a Vulnerability

Report a security vulnerability in private. A public GitHub issue, discussion, or pull request leaves the report visible before it can be fixed.

Use either of these:

- [Open a private vulnerability report](https://github.com/parterburn/dabble.me/security/advisories/new) on this repository. GitHub keeps the report visible only to the maintainer until it is published.
- Email [hello@dabble.me](mailto:hello@dabble.me?subject=Security) with the subject line **Security**. That address is read by the person who runs Dabble Me.

Include what you can of the following:

- What is wrong, and what someone could do with it
- Steps to reproduce, or a proof of concept, using an account you control
- The part of the product affected: the website, the API (`/api/v1`), the MCP server (`/mcp`) and its OAuth flow, inbound email, exports, or the iOS app
- A way to reach you, and whether you want to be credited

Describe what you were able to reach. Leave other people's journal entries, images, and account data out of the report. If a test reaches someone else's account, stop. Do not copy it, change it, or keep it.

We will acknowledge a report within 3 business days, say whether we accept it, and write again as we work on a fix. Please give us time to ship a fix before publishing details. We aim to resolve an accepted report, or agree on a disclosure date with you, within 90 days.

There is no bug bounty. We will credit you in the fix notes when you ask to be named.

## Scope

These are in scope when they affect [dabble.me](https://dabble.me), this repository's `main` branch, or the current App Store build of the iOS app:

- The website and the signed-in journal
- The API at `/api/v1`
- The remote MCP server at `/mcp`, including OAuth
- Inbound email that creates journal entries
- Sign-in, passkeys, two-factor authentication, sessions, and exports

These are out of scope:

- Denial-of-service and high-volume traffic
- Social engineering, phishing, or physical access
- A report that needs a device, inbox, or account you do not own
- Stripe, Mailgun, Cloudflare, Sentry, Amazon S3, and other third-party services
- Scanner output and missing headers with no demonstrated effect
- Self-XSS that requires someone to paste code into their own browser
- An outdated fork, or a copy of Dabble Me that you host yourself

A flaw in this repository still belongs here when it would affect dabble.me. Securing a copy you run is your own responsibility.

## Testing

Test only as far as you need to confirm the issue, and only with accounts you own. Stop once you have a reliable proof of concept, then send the report.

While you test:

- Stay inside accounts you own
- Leave the service usable for everyone else
- Skip automated scans that send a high volume of requests

## Supported versions

Security fixes ship to the service running at dabble.me, which tracks `main`, and to the current App Store release of the iOS app. Older commits and self-hosted copies are not maintained.

## Safe harbor

Research done in good faith, within this policy, and without privacy violations, service disruption, or destruction of data, will not lead us to pursue legal action for that research. This covers our response. It does not bind anyone else, including a person whose account was affected.
