# Dabble Me for Android: scoping

Status: scoping only, nothing built. Written 2026-11-21 against iOS build 109.

## Bottom line

- **It's a second app, not a port.** About 22,000 lines of Swift/SwiftUI (84 files) get rewritten in Kotlin + Jetpack Compose. The Rails API (`/api/v1`) is reused as is, apart from three small server changes.
- **Parity: roughly 70 to 80 focused working days, about 14 to 16 weeks full time.** A useful MVP (sign in, read, write, photos, reminder, widget) is about **7 weeks**, plus Google Play's mandatory 14-day closed test before the first public release. These are deliberately conservative; if the iOS app's pace holds, they shrink, but the editor, dictation and AI ranges won't shrink much because they're device testing, not typing.
- **The three risky parts:** the rich text editor, dictation quality, and on-device AI coverage. Everything else has a well-trodden Android equivalent.
- **Don't build it yet without a demand number.** The repo has no Android usage data of its own (see [Demand signals](#demand-signals)). The website already tells Android users "not yet", and email plus the mobile web covers them today.
- **Billing is not a blocker.** The iOS app sells nothing in-app, and Android can do the same. Play Billing is only needed if Pro ever sells in either app.

## Feature inventory and Android mapping

Effort is in focused working days for one developer with Claude doing most of the typing, including tests. "Days" here assume the iOS app is the spec, so design questions are already answered.

| Area | iOS today (framework) | Android equivalent | Days | Risk |
|---|---|---|---|---|
| Project skeleton, theming, fonts, Slab icons, navigation (Today / Journal / Search / Settings tabs) | SwiftUI, `Assets.xcassets`, Instrument Serif | Compose + Material 3 (heavily themed), Navigation Compose, vector drawables from the same Slab SVGs | 3 | Low |
| API client, models, token refresh, 401 handling | `URLSession`, `Codable`, `TokenProvider` | Retrofit or Ktor + kotlinx.serialization, OkHttp authenticator for the refresh-once rule | 2 | Low |
| Token storage | Keychain (`KeychainStore`) | Android Keystore + DataStore (Tink-encrypted). `EncryptedSharedPreferences` is deprecated | 0.5 | Low |
| Native sign in / sign up / 2FA code | `AuthFormView`, `/api/v1/session`, `/registration` | Same endpoints, Compose forms, Credential Manager for saved passwords | 1.5 | Low |
| Passkeys | `ASAuthorizationPlatformPublicKeyCredentialProvider`, `webcredentials:dabble.me` | Credential Manager (`GetPublicKeyCredentialOption`) + `assetlinks.json` | 1.5 | Medium: needs the Rails origin change below, and Google Play services on the device |
| Account deletion | `DeleteAccountView` (password or passkey) | Same endpoints | 0.5 | Low |
| Today (prompt, On This Day, last-five-days dots, entry count) | SwiftUI | Compose | 2 | Low |
| Journal timeline, month scrubber, Photos grid, Songs list | `List`, custom scrubber | `LazyColumn` / `LazyVerticalGrid`, Paging 3 | 3 | Low |
| Entry detail (On This Day under it, prev/next, swipe actions, back trail) | `EntryDetailView` (1,400 lines) | Compose | 3 | Low |
| **Rich text editor** (bold/italic/underline/links, bullets, numbered and nested lists, rules, `#` completion, lightbulb row) | `UITextView` + `RichTextEditorModel` + `RichText` (~1,500 lines) | Compose `BasicTextField` with a custom span model, or `compose-rich-editor` as a base. Must round-trip `Api::EntryDocument` exactly | 6–9 | **High.** Compose's rich-text editing is far less mature than `UITextView`/`NSAttributedString`. Cursor, IME and list-indent bugs are where the time goes |
| Composer (date picker, drafts with photos, merge-into-existing-day, template) | `ComposeView` (1,900 lines), `DraftStore` | Compose + Room or files for drafts | 3 | Medium (it's large, not hard) |
| Photos: pick, re-encode to ≤2400px JPEG, strip EXIF/GPS, presigned S3 PUT, collage processing state | PhotosUI, ImageIO | Photo Picker (no permission needed), `ImageDecoder`/`Bitmap.compress` (drops EXIF), OkHttp PUT | 2 | Low. Verify GPS is really gone with a test, as iOS does |
| Photo viewer (zoom, save, share) | `PhotoViewer` | Telephoto or a Coil-based zoomable, `MediaStore` save, share sheet | 1.5 | Low |
| Search + hashtag cloud | `SearchView` | Compose | 1.5 | Low |
| Stats (tiles, day grid, monthly chart) | Swift Charts | Vico, or plain Compose `Canvas` | 2.5 | Low |
| Rewind (story cards, names and places) | `NaturalLanguage` name recognition + Foundation Models | Card pager in Compose. ML Kit Entity Extraction finds addresses and dates but **not person names**, so use the iOS fallback (capitalized words) or Gemini Nano where present | 4 | Medium |
| Spotify embedded player | `WKWebView` + iFrame API | `WebView` + the same iFrame API | 1 | Low |
| Settings (email schedule, reminders, past-entry filters, dated hashtags, template, accessibility text size, plan link) | SwiftUI forms | Compose forms, same endpoints | 3 | Low |
| Daily reminder notification (local, scheduled two weeks ahead, skipped once written, actions) | `UserNotifications`, `BGTaskScheduler` | `AlarmManager` exact/inexact alarms + WorkManager for the background top-up, notification actions | 2 | Medium: OEM battery killers (Samsung, Xiaomi) delay or drop alarms; Android 13+ needs the notification permission; exact alarms need a special permission, so use inexact |
| Home-screen widget (date, five dots, prompt or Rewind, photo, rotation through the day, per-widget config, deep links) | WidgetKit + App Group snapshot + `AppIntentConfiguration` | Jetpack Glance widget, snapshot in DataStore, `GlanceAppWidget` configuration activity, WorkManager for the timed rotation | 4 | Medium. Glance's layout is limited (no free-form text measuring), and Android widgets refresh on the system's terms |
| Lock Screen widgets | WidgetKit accessory families | None on phones (Android has no lock-screen widgets outside tablets/hubs) | 0 | Dropped |
| Control Center "New Entry" control, Action button, Shortcuts | `ControlWidget`, App Intents | Quick Settings tile (`TileService`), static app shortcuts (long-press icon), maybe a small 1×1 "New entry" widget | 1 | Low |
| Home-screen quick actions | `UIApplicationShortcutItems` | Static/dynamic shortcuts (`ShortcutManagerCompat`) | 0.5 | Low |
| Universal links | `applinks:dabble.me`, AASA | Android App Links with `autoVerify` intent filters + `assetlinks.json` | 1 | Low |
| App lock (Face ID), privacy cover in the app switcher | `LocalAuthentication`, `PrivacyCover` | `BiometricPrompt` (class 3 or device credential), `FLAG_SECURE` on the window | 1 | Low |
| Calendar agenda in the composer | EventKit | `CalendarContract` provider + `READ_CALENDAR` | 1.5 | Low |
| Shake for a random memory | `motionEnded` | `SensorManager` accelerometer | 0.5 | Low |
| Splash with typing wordmark | `SplashView` | `core-splashscreen` + Compose animation | 0.5 | Low |
| **Dictation** (record WAV, one-pass on-device transcription with names to expect, BERT cleanup tagger, opt-in AI fix) | `SpeechTranscriber` (iOS 26), Core ML tagger, Foundation Models | See [Dictation](#dictation). Recommended: whisper.cpp or Parakeet via sherpa-onnx on device, the same cleanup tagger converted to ONNX or TFLite | 6–9 | **High.** Quality, model size and speed vary hugely across devices |
| **On-device AI** (Reflection + chat, Today's personal prompt, hashtag suggestions, Rewind sentences) | Foundation Models, `permissiveContentTransformations` | ML Kit GenAI Prompt API on Gemini Nano (AICore) | 5–7 | **High.** See [On-device AI](#on-device-ai) |
| Tests (unit, Compose UI, screenshot) | XCTest, XCUITest | JUnit + Robolectric, Compose UI tests, Roborazzi or Paparazzi screenshots | spread across areas, plus 3 for the end-to-end suite | Low |
| Store listing, privacy (Data safety form), signing, CI | App Store Connect, Xcode Cloud | Play Console, Play App Signing, GitHub Actions building an AAB and uploading with Gradle Play Publisher | 2 | Low, but see the 14-day closed test |

**Total: the rows add up to about 70 to 78 working days, plus about 2 for Rails: call it 14 to 16 weeks full time.** The spread is almost entirely the editor, dictation and AI.

## Rails changes needed

All small. None touch the existing iOS behavior.

1. **`/.well-known/assetlinks.json`** (new route beside `AppLinksController#apple_app_site_association`). One statement with both `delegate_permission/common.handle_all_urls` (App Links) and `delegate_permission/common.get_login_creds` (passkeys and saved passwords), the package name and the Play App Signing SHA-256 certificate fingerprint. Half a day with a spec.
2. **WebAuthn origins for Android.** `config/initializers/webauthn.rb` only allows `https://dabble.me`. A passkey assertion from an Android app carries the origin `android:apk-key-hash:<base64url of the signing cert SHA-256>`, so `Api::V1::PasskeyAssertion#passkey_user` would reject every Android passkey sign-in today. Add that origin to `allowed_origins` in production (and the debug key's hash in development). Half a day. This is the change most likely to be missed.
3. **An Android OAuth client.** `MobileApp` is hard-wired to `dabble-me-ios` (client ID, name shown under Connected Apps, redirect scheme). Either generalize it to two first-party clients (`dabble-me-ios`, `dabble-me-android`) so Connected Apps on `/security` lists them separately and each can be revoked on its own, or reuse the iOS client. Recommend the separate client: about a day, mostly specs.
4. **`LINK_PATHS` reuse.** App Links use `pathPattern` in the app's own manifest, not on the server, so the server list just needs mirroring in the manifest. No server change.

Not needed: push infrastructure (reminders are local on both platforms), any new entry or stats endpoints, Play Billing (see below).

Optional later: **Google Play billing.** Only if Pro sells in-app. Since 2025's Epic v. Google injunction, Google no longer requires Play Billing for US users, and an app that neither sells nor links needs no enrollment at all. Linking out to buy on dabble.me (the iOS app's US-only Settings → Plan link) needs enrollment in Play's External Content Links program, which charges **10% on subscriptions bought within 24 hours of following the link**, with fees live since October 1, 2026. That's worse than linking out on iOS, so the default should be: **no purchase link on Android at first**, and mention "manage your plan on dabble.me" as plain text if that passes review. If Pro ever sells in-app on both stores, that's the StoreKit 2 backlog item plus Play Billing Library and Real-Time Developer Notifications to Rails: a separate project of 2 to 3 weeks.

## The risky parts

### Rich text editor

The iOS editor leans on `UITextView` and attributed strings, which handle IME, selection, undo and spans for free. Compose's `BasicTextField` with `TextFieldState` handles plain text well, but spans (bold over a selection, links, list markers that survive Enter and Backspace, four-space nested indents) are hand-built. Open-source `compose-rich-editor` gets part of the way but doesn't model the exact `EntryDocument` blocks.

What I'd do: build the document model and its round-trip tests first (they can mirror `DabbleMeTests` rich-text cases and `Api::EntryDocument` specs), then the editor on top, and test on Gboard and Samsung Keyboard specifically, since keyboards are where Android editors break. Fallback if it drags: ship the MVP with plain text plus lists, and keep "edit formatting" on the web for a release.

### Dictation

There's no `SpeechTranscriber`. The options, best first for this app:

- **On-device Whisper (whisper.cpp) or Parakeet (sherpa-onnx), record then transcribe.** Matches the iOS design exactly and works offline, including on a device without Google services. Costs: a 75 to 500 MB model download, slow on mid-range phones (a minute of speech can take tens of seconds on older chips), and English-centric for Parakeet. Whisper takes an initial prompt, which can carry the custom vocabulary and hashtags the way `contextualStrings` does.
- **Android `SpeechRecognizer` with `EXTRA_PREFER_OFFLINE`.** Free and small, but it's built for short commands, stops on pauses, and quality and offline support vary by OEM. Roughly the "no better than the keyboard" result that got build 83's mic removed.
- **ML Kit GenAI speech recognition** (Gemini Nano). Alpha as of November 2026 and limited to recent flagships. Watch it, don't build on it.

The cleanup tagger (Hex's BERT token classifier) is portable: convert the Core ML model back to ONNX or TFLite and run it with ONNX Runtime Mobile. The Swift wrappers (`CleanupGuard`, `CleanupReconstruction`, `CleanupTokenizer`) port line for line.

Recommendation: leave dictation out of the MVP. Gboard's voice typing is decent on Android and is the honest baseline. Add record-then-transcribe in phase 3 only if Paul finds the keyboard lacking on a real phone.

### On-device AI

iOS uses Foundation Models on every Apple Intelligence device. Android's equivalent is the ML Kit GenAI Prompt API on Gemini Nano via AICore. As of November 2026 it's **Beta**, runs only on recent flagships (Pixel 9 to 11, Galaxy S25/S26 and Z series, some OnePlus, OPPO, Xiaomi, Honor, Motorola), runs only while the app is in the foreground, and has a per-app quota. Its safety filtering may refuse hard journal entries the way Foundation Models' default guardrails did, and there's no `permissiveContentTransformations` equivalent to switch to. Test that early with the same hard-entry text used for `reflectsOnAHardEntry()`.

What I'd do: hide Reflection, personal prompts, hashtag suggestions and Rewind's sentences where Gemini Nano isn't available, exactly as iOS hides them without Apple Intelligence. Don't send journal text to a cloud model to fill the gap; that breaks the "on device only" promise in the README and the privacy labels.

### Smaller risks

- **Device fragmentation.** Test at least one Samsung (One UI) build, since that's where notification delays and keyboard quirks show up.
- **Play's closed-testing rule.** Personal developer accounts created after November 13, 2023 must run a closed test with **at least 12 testers opted in for 14 continuous days** before production access. Plan for it: recruit testers from Pro users who've emailed asking for Android. An organization developer account is exempt but needs a D-U-N-S number.
- **Google's developer verification.** Google announced identity verification for Android developers, including apps installed outside Play. A Play Console account already verified should cover it, but check the current rules when the account is made.

## Phased plan

**Phase 0: decide (1 to 2 hours, no code).** Get a demand number (below). If under a few percent of active writers are on Android, stop here.

**Phase 1: MVP, about 34 days (7 weeks).** Free and Pro users can do what the iOS app's free tier does, plus Pro writing.
- Rails: `assetlinks.json`, Android WebAuthn origin, Android OAuth client.
- Sign in / sign up / 2FA / passkeys, account deletion (Play requires in-app deletion too).
- Today, Journal list, entry detail, Search.
- Composer with **plain text and lists only**, drafts, photos with EXIF stripping.
- Daily local reminder.
- One medium Glance widget: date, five dots, prompt.
- App Links, app lock, quick-launch shortcuts.
- Internal track, then the 14-day closed test with 12+ testers.

**Phase 2: parity minus the hard parts, about 20 to 23 days (4 to 5 weeks).** Full rich text editor, Stats, Photos grid, Songs and the Spotify player, On This Day under an entry, all Settings pages, calendar row, widget Rewind mode with photo and rotation, Quick Settings tile, shake for a memory.

**Phase 3: the device-dependent parts, about 15 to 20 days (3 to 4 weeks).** Gemini Nano features where available, Rewind, then dictation if the keyboard proves not good enough.

## Testing

**Skip the Skylight for anything beyond "does it launch".** Hacked Skylight frames typically run old, OEM-customized Android with no Google Play services. Without Play services there's no Credential Manager passkeys, no Play Store install, no AICore/Gemini Nano, and the screen is a landscape tablet, not a phone. It can't test the things most likely to break.

What to use instead:
- **Android Emulator (free).** Covers most of Phase 1 and 2: Pixel phone images with Google Play, API levels from the minimum up, passkeys (with a Google account and screen lock set on the emulator), widgets, notifications, App Links. Runs fine on an Apple Silicon Mac in Android Studio.
- **One real Pixel, about $150 to $250 used.** A Pixel 9 or 9a is the floor for Gemini Nano (Nano 3), so buy that rather than a Pixel 7 or 8 if on-device AI matters. Needed for dictation speed, widget behavior on a real launcher, and Gboard.
- **One Samsung, borrowed or cloud.** Firebase Test Lab (free tier: a handful of physical-device runs a day) or Samsung Remote Test Lab for One UI quirks. No purchase needed.
- **CI.** GitHub Actions builds and runs JVM unit tests and Robolectric/Roborazzi screenshot tests on every push. Emulator UI tests on Actions are slow and flaky; run those locally or in Firebase Test Lab.
- **Minimum SDK.** Recommend Android 9 (API 28) as the floor for Credential Manager passkeys and to cover about 90% of active devices; Photo Picker is backported that far through Play services.

## Demand signals

The repo has none worth counting:
- No user-agent or device logging in the database. Devise keeps sign-in IPs, not browsers.
- Google Analytics 4 is on the marketing and app layouts (`GOOGLE_ANALYTICS_4_ID`). **This is the quickest real number:** GA4 → Reports → Tech → Tech details → Operating system, last 90 days, filtered to signed-in pages (the app layout) rather than marketing traffic.
- `EmailProcessor#mobile_signature_pattern` strips "Sent from my Android / Galaxy / Pixel" signatures from replies but doesn't record them. A one-off console count over recent `original_email` rows (decrypted in Ruby, never in SQL) would show what share of email writers reply from Android. That's a better signal than web traffic, since email is how most people write.
- The marketing FAQ (`welcome/journal_app.html.erb`, `ApplicationHelper` FAQ) already says there's no Android app. Searching the support inbox for "Android" would show whether anyone asked.

Ask for a go/no-go threshold before building: for example, "at least 10% of active writers on Android, or 20+ people asking".
