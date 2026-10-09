# Dabble Me plugin

Connects to the existing Dabble Me Streamable HTTP server at https://dabble.me/mcp using host-managed OAuth (PKCE S256, scope mcp:access). No API keys or server deployment are needed. Requires a Dabble Me PRO account with a passkey or two-factor authentication.

Includes three skills: find-memories, reflect-on-your-journal, and write-journal-entry. Uses the existing Dabble Me icon.

Public server-card and OAuth metadata were verified on 2026-10-08. Tool contracts and limitations were inspected in app/lib/mcp and app/services/mcp. Authenticated tools/list and account actions require installation and user OAuth connection; they have not been exercised by this package build. No journal entries were read or created.

After installation, connect Dabble Me through the host, ask for one recent entry, then try a dated memory search and a period review. Test saving only with an explicitly requested entry; confirm the returned success and URL. Do not create test entries merely to validate authentication.

Package from the plugins directory with: `python3 -m zipfile -c /tmp/dabble-me-plugin.zip dabble-me`

## Claude directory submission

Use repository `https://github.com/parterburn/dabble.me` and plugin path `plugins/dabble-me`. Track `main` after the compatibility changes merge. Claude reads `.claude-plugin/plugin.json` and `.mcp.json`; portable clients read the root `plugin.json` and `mcp.json`. Both use the same existing OAuth server and skills. Claude uses the transport name `http` for Streamable HTTP.

Validate locally with `claude plugin validate ./plugins/dabble-me`. Keep the identity, version, descriptions, and connection synchronized across formats when releasing updates.

## OpenAI review materials

The portable manifest includes five positive and three negative review cases, the demo link (https://urg.ai/dbl-mcp), and release notes. The demo link resolves to a public Loom page; video playback has not been verified. These cases are drafted and have not been run against the reviewer account. Prepare the dated sample entries described in the cases before running them. Run read cases before write cases, and supply reviewer credentials only through the portal's secure fields.

The logo asset and manifest references are verified in private plugin v0.1.5. Rendering on the signed-in ChatGPT plugin page remains unverified.
