# Dabble Me for iOS

Native SwiftUI companion to the email journal: Today (prompt + On This Day), the Journal timeline with List / Stats / Photos views, search with a hashtag cloud, writing and editing with rich text and photos, reminders, a Face ID lock, a home-screen widget, and on-device Apple Intelligence.

Email is still the primary way people write. Plan rules (see `ios/AppStore/metadata.md` → Decisions): everyone can sign in, read, write text, and see Stats, Photos and the widget; photos, editing/deleting, search, On This Day, reminders and on-device AI are PRO.

## Requirements

- Xcode 27+, iOS 18+ deployment target, Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Getting started

```bash
cd ios
xcodegen generate        # creates DabbleMe.xcodeproj (gitignored; project.yml is the source of truth)
open DabbleMe.xcodeproj
```

Debug builds point at `http://localhost:3000` and Release builds at `https://dabble.me` (the `DABBLE_BASE_URL` setting in `project.yml`). To use a local server:

```bash
# from the repo root
bundle exec rails db:migrate    # or db:seed: registers the iOS OAuth client
MAIN_DOMAIN=localhost ... bundle exec puma -p 3000 -C config/puma.rb   # see AGENTS.md
```

The simulator reaches `localhost` directly. On a phone, "localhost" is the phone itself: start Puma with your Mac's Bonjour name allowed (`RAILS_DEVELOPMENT_HOSTS=<name>.local`, see `scutil --get LocalHostName`), then in a Debug build tap **Server** on the sign-in screen → **Other…** and enter `http://<name>.local:3000`. Run `bundle exec sidekiq` too if you want photos and collages to finish processing. The seeded `admin@dabble.ex` / `dabble` account is PRO.

## How sign-in works

1. The app opens `/oauth/authorize` in `ASWebAuthenticationSession`. That page is the normal dabble.me sign-in: password, passkey, or 2FA. The session shares Safari cookies, so someone already signed in on the web just taps through.
2. Doorkeeper skips the consent screen for this first-party client (`MobileApp` in `app/lib/mobile_app.rb`) and redirects to `me.dabble.app:/oauth/callback?code=…`.
3. The app exchanges the code using PKCE (public client, no secret) for an `app:journal` access token plus a refresh token, and stores both in the Keychain.
4. API calls go to `/api/v1/*` with `Authorization: Bearer …`. On a 401 the app refreshes once, and signs out if the refresh is rejected.

`app:journal` tokens can't call `/mcp`, and MCP tokens can't call `/api/v1`. App tokens survive a PRO downgrade or passkey removal, since those only gate MCP. A password, email, or 2FA change signs the app out, and so does removing "Dabble Me for iOS" under Connected Apps on `/security`.

## API

| Method | Path | Notes |
|---|---|---|
| GET | `/api/v1/me` | account, plan, `today` in the user's journal time zone |
| GET | `/api/v1/entries?page=&per=&year=&month=&photos=1` | newest first, 20 per page by default (max 50); `photos=1` lists only entries with a photo (Journal > Photos) |
| GET | `/api/v1/entries/:id` | full entry: `body_text` (light Markdown), `document` (editable structure or null), songs, `web_url` |
| GET | `/api/v1/entries/random` | |
| GET | `/api/v1/entries/on_this_day` | PRO |
| POST | `/api/v1/entries` | PRO. `{date, document \| body, uploaded_image_keys?}`; merges into an existing entry on that day, like the web. One photo is stored as-is; 2–8 (or any added to a day with a photo) become a collage, and the entry reports `image_processing: true` from the moment the job is queued |
| PATCH | `/api/v1/entries/:id` | PRO. Any of `{document, remove_image, uploaded_image_keys}`. `document` only when the entry's `document` is non-null; new photos join the entry's photo in a collage, or replace it with `remove_image` |
| DELETE | `/api/v1/entries/:id` | PRO |
| GET | `/api/v1/search?q=&page=` | PRO, same syntax as web search |
| GET | `/api/v1/today` | Today tab: entry, On This Day (PRO), daily prompt, `current_streak` |
| GET | `/api/v1/entries/months` | month index for the timeline and scrubber |
| GET | `/api/v1/entries/memory_days?days=30` | PRO. Upcoming days with memories (counts only) for On This Day reminders |
| GET | `/api/v1/stats` | Journal > Stats: totals, streaks, writing days in the past year, 12 months, top hashtags (`Api::JournalStats`) |
| GET | `/api/v1/hashtags?days=365` | PRO. Hashtag counts for the Search tag cloud (`Api::HashtagCounts`) |
| POST | `/api/v1/image_uploads` | PRO. `{photos: [{filename, content_type}]}` (max 8) → presigned S3 PUTs; the keys go to `POST /entries` |

**Rich text editing.** The app never parses or sends raw HTML. `Api::EntryDocument` turns stored HTML into a `document`: a list of paragraph / bullet / number / rule blocks made of text runs that may be bold, italic, underlined or linked. That covers what the web editor (Summernote) and email ingestion produce, including `<div>` lines from email and `<hr>` between merged replies. The app edits the document in a native text view (bold, italic and underline from the text's Format menu; typing "- ", "* " or "1. " starts a list; the bar has "+" for photos and hashtag suggestions, and link; dictation is the keyboard's own) and sends it back, and the server rebuilds clean HTML from it (`to_html`). Entries with anything the document can't represent — inline styles, blockquotes, images, DabbleMeGPT replies, nested lists — come back with `document: null` and show "Edit on dabble.me", so an in-app edit can never drop formatting.

**Widget.** `DabbleMeWidget` (WidgetKit) reads a `WidgetSnapshot` the app writes to the `group.me.dabble.ios` App Group after each refresh: streak, whether today is written, today's prompt (the personal Apple Intelligence one when there is one, unless the Face ID lock is on) and (only if turned on in Settings → Privacy) a count of On This Day memories. Never entry text. Tapping it opens `me.dabble.app:/write` or `:/today`.

**On device only.** Hashtag suggestions, "Reflect on This Entry" (the on-device version of the web's DabbleMeGPT life-coach reply) and Today's "Prompt from My Recent Entries" use Apple Intelligence's on-device model (`FoundationModels`, iOS 26+, hidden where unavailable). Reminders, the Face ID lock and drafts are local too.

**Photos** are re-encoded on the device to a JPEG of at most 2400px, with all metadata removed (including GPS) before upload. The server then processes them the same way as MCP uploads (`ProcessEntryImageJob`).

## Tests

```bash
xcodebuild -project DabbleMe.xcodeproj -scheme DabbleMe -destination 'platform=iOS Simulator,name=iPhone 17' test
```

The tests cover PKCE, day handling across time zones, JSON decoding, rich text layout, round-trips and list indents, GPS stripping, the widget's day/streak rollover, and reading hashtags from model replies. API behavior is covered by `spec/requests/api_v1_spec.rb` on the Rails side.

### UI tests against a local server

The UI tests that need a server skip unless you pass a token from `bundle exec rails ios:demo_account`:

```bash
TEST_RUNNER_DABBLE_TOKEN=<token> xcodebuild test -project DabbleMe.xcodeproj -scheme DabbleMe \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:DabbleMeUITests
```

- Start Puma before Sidekiq, a few seconds apart: `.env` is a 1Password pipe, and two processes opening it at once can leave one without AWS keys.
- **Face ID lock test:** enroll Face ID on the simulator (`xcrun simctl spawn <device> notifyutil -s com.apple.BiometricKit.enrollmentChanged 1` and then `-p` the same name). Run a helper that sends one match (`xcrun simctl spawn <device> notifyutil -p com.apple.BiometricKit_Sim.pearl.match`) whenever `$TEST_RUNNER_DABBLE_DEBUG_DIR/faceid-match` appears, then deletes the file. Also set `TEST_RUNNER_DABBLE_FACE_ID=1`.
- **App Store screenshots:** set `TEST_RUNNER_DABBLE_SCREENSHOT_DIR` and run `ScreenshotTests` on the iPhone 18 Pro (1206 × 2622) and iPad Pro 13" simulators. Reset the demo account first so Today has no entry yet.
- **First-time hashtag suggestions:** `bundle exec rails ios:empty_account` prints a token for a PRO account with no hashtags; pass it as `TEST_RUNNER_DABBLE_EMPTY_TOKEN`.
- **Widget test:** `WidgetTests` adds the widget to the simulator's home screen and screenshots it; set `TEST_RUNNER_DABBLE_WIDGET=1`.
- **Apple Intelligence** works in the simulator when the Mac has it turned on; the tests that use it skip those steps otherwise.

## Shipping checklist

- [ ] Deploy the Rails side first. The `CreateMobileAppOauthApplication` migration registers the `dabble-me-ios` OAuth client.
- [ ] Register the App ID `me.dabble.ios` under team B79A4CAS56 (Xcode's automatic signing does this on first device run or archive).
- [ ] Create the App Store Connect record. Privacy labels: email address, user ID, other user content, photos. All are linked to the user, used for app functionality, and not used for tracking (matches `PrivacyInfo.xcprivacy`).
- [ ] App Review notes: provide a demo PRO account. Explain that new accounts can be created on the sign-in page and deleted under Settings → Delete Account.
- [ ] Purchase links: only Settings → Plan, and only on the US App Store (`Storefront.current`); nowhere else in the app.
