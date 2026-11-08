# App Store listing: Dabble Me – Private Journal

Copy for App Store Connect (app ID 6832151292, bundle ID `me.dabble.ios`). Character limits are noted where Apple enforces one. Keep this in sync with what the shipped build actually does.

## App Information

| Field | Value |
|---|---|
| Name (30) | Dabble Me – Private Journal |
| Subtitle (30) | Daily diary, photos & memories |
| Primary category | Lifestyle |
| Secondary category | Productivity |
| Content rights | Does not contain, show, or access third-party content |
| Age rating | 4+ (no objectionable content; entries are private and never shared with other users) |
| Copyright | 2026 Dabble Dev LLC |

## Version 1.0

**Promotional text (170)**

> Rediscover what you wrote on this day years ago, keep your writing streak going, and see your year in photos and stats. Private, and yours to keep.

**Description (4,000)**

> Your life, written down and remembered.
>
> Dabble Me is a private journal for the moments you don't want to forget. Write about your day, add photos, and watch it turn into something priceless: years of memories you can read back through, search, and rediscover.
>
> ON THIS DAY
> See what you wrote on today's date one, five, or ten years ago, right on the Today screen. Turn on a morning reminder on days you have memories waiting.
>
> WRITE YOUR WAY
> • Bold, italic and underline, links, and lists that start as you type "- " or "1." 
> • Add up to 8 photos. Several become a beautiful collage automatically
> • Edit entries later, photos included
> • A daily writing prompt, written just for you from your recent days (on devices with Apple Intelligence)
> • Unfinished entries are saved as you type, even if the app closes
> • Prefer email? Reply to Dabble Me's "How was your day?" email and it becomes an entry too. Choose its days, time and time zone right in the app
>
> BUILD THE HABIT
> • A daily reminder to write, skipped on days you already have
> • A home-screen and Lock Screen widget with your writing streak
> • Stats: entries, words, current and longest streak, a year of writing at a glance, and your most-used hashtags
>
> YEARS OF MEMORIES, ONE TAP AWAY
> • Your whole journal by month, with a timeline scrubber to jump years back
> • Photos view: every day you captured, in one grid
> • Search every word you've ever written, or tap your #hashtags
> • Tap an entry to read it right in the timeline; swipe to reflect or edit
> • Tap an entry's date to see how long ago it was
> • Long-press any entry to preview it
> • Give a #hashtag a date (a birthday, an anniversary) and see how old your kids were, or how long it had been, in every entry
> • Random entry: rediscover a moment you'd forgotten
> • Photos full screen with pinch to zoom; save or share the ones you love
> • Pinch to make entries easier to read
>
> APPLE INTELLIGENCE, ON YOUR DEVICE
> On supported iPhones and iPads, Dabble Me responds to an entry with a warm, thoughtful reflection and a question to keep you writing (just pull down on it), suggests which of your hashtags fit as you write, and writes each day's prompt from your recent days. It all runs on your device; your journal isn't sent anywhere for it.
>
> ASK AI ABOUT YOUR JOURNAL
> Connect Claude or ChatGPT to your journal and ask things like "What made me happiest this year?" or "When did I last go camping?" You approve access, and you can remove it any time.
>
> PRIVATE BY DESIGN
> • No social feed, no ads, no tracking
> • Lock the app with Face ID; your journal is hidden in the app switcher
> • Reminders and widgets never show what you wrote
> • Photo location data is removed before upload
> • Sign in with a passkey, password, or two-factor code
> • Export everything, any time
>
> Free accounts can read their journal, write entries, and see their stats. Photos, search, On This Day, reminders, Apple Intelligence features, and AI connections are part of Dabble Me PRO.

**Keywords (100)**: these don't repeat words already in the name, which Apple indexes anyway, and use no third-party trademarks (guideline 2.3.7).

```
diary,daily,memories,on this day,reflection,gratitude,photo,writing,mood,prompts,streak,widget,ai
```

**What's New**: leave blank for 1.0 (submitted with build 17 or later; build 9 was never submitted).

| Field | Value |
|---|---|
| Support URL | https://dabble.me/support |
| Marketing URL | https://dabble.me |
| Privacy Policy URL | https://dabble.me/privacy |

## App Privacy ("nutrition label")

Data used to track you: **none**. Data linked to you, all for **App Functionality** only:

| Data type | Why |
|---|---|
| Contact Info → Email Address | Account identity and sign-in |
| User Content → Other User Content | Journal entries |
| User Content → Photos or Videos | Photos attached to entries |
| Identifiers → User ID | Account identity |

The app has no analytics or crash SDKs, and these answers match `DabbleMe/Resources/PrivacyInfo.xcprivacy`. Not collected: Apple Intelligence features run on the device; reminders, the Face ID setting and drafts stay on the device; the widget reads a streak count the app stores in its App Group.

## App Review information

- **Sign-in required:** yes. Create a production demo account (for example `appreview@dabble.me`) on **PRO**, with a few entries that include photos and hashtags, and with password sign-in (no 2FA) so the reviewer can get in.
- **Notes for the reviewer:**

> Dabble Me is a private journal; the app is a free companion to the dabble.me service, and it sells nothing in the app. Sign in with the demo account above on the sign-in page that opens. Photos, search, On This Day and AI connections are PRO features; the demo account is PRO. Accounts can be created with "Create a Free Account" on the first screen and deleted in Settings → Delete Account (we email a link to finish deletion on dabble.me, where it's confirmed with the account password).

- **Export compliance:** the app uses only standard HTTPS (`ITSAppUsesNonExemptEncryption = NO`).

## Screenshots

In `ios/App Store Screenshots/`: **iPhone 6.3"** at 1206 × 2622 (iPhone 18 Pro simulator) and **13" iPad** at 2064 × 2752, both from the made-up demo account (never a real journal), via `ScreenshotTests` (see `ios/README.md`):

1. Today: the date, today's prompt, and On This Day
2. Journal timeline with photos and month sections
3. An entry with formatting, a list and a photo
4. Writing an entry with the formatting bar, photos and on-device hashtag suggestions
5. Journal > Photos
6. Journal > Stats
7. Search: your hashtags this year
8. Search results for #hiking

`bundle exec rails ios:demo_account` seeds that account locally. It needs valid AWS credentials in `.env` for the photos. Hashtag suggestions need a simulator on a Mac with Apple Intelligence turned on; without it, shot 4 just has no suggestions row.

## Decisions

- **In-app purchase:** ship as a free companion app (guideline 3.1.3(f)) with no in-app purchasing. On the **US App Store only**, Settings → Plan links to dabble.me/subscribe (US storefront exception in guideline 3.1.1(a), May 2025), detected with StoreKit's `Storefront.current`; elsewhere the plan is plain text. If App Review objects, drop the link.
- **Free vs PRO in the app:** free accounts read and write text entries and see Stats, the Photos view and the widget; photos, editing/deleting, search (and its hashtag cloud), On This Day, reminders, AI connections and on-device AI features are PRO. Dictation is the keyboard's own (no in-app mic). Face ID lock and drafts are for everyone.
- **iPad:** supported in 1.0, so the submission needs the 13" iPad screenshot set too.
