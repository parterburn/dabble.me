# Dabble plugin

Connects to the existing Dabble Me Streamable HTTP server at https://dabble.me/mcp using host-managed OAuth (PKCE S256, scope mcp:access). No API keys or server deployment are needed. Requires a Dabble Me PRO account with a passkey or two-factor authentication.

Includes three skills: find-memories, reflect-on-your-journal, and write-journal-entry. Uses the existing Dabble Me icon.

Public server-card and OAuth metadata were verified on 2026-10-08. Tool contracts and limitations were inspected in app/lib/mcp and app/services/mcp. Authenticated tools/list and account actions require installation and user OAuth connection; they have not been exercised by this package build. No journal entries were read or created.

After installation, connect Dabble Me through the host, ask for one recent entry, then try a dated memory search and a period review. Test saving only with an explicitly requested entry; confirm the returned success and URL. Do not create test entries merely to validate authentication.

Package from the repository root with: python3 -m zipfile -c /tmp/dabble-plugin.zip plugins/dabble
