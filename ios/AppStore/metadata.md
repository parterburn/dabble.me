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

> Rediscover what you wrote on this day years ago, capture today with photos, and ask Claude or ChatGPT about your own journal. Private, and yours to keep.

**Description (4,000)**

> Your life, written down and remembered.
>
> Dabble Me is a private journal for the moments you don't want to forget. Write about your day with photos, then watch it turn into something priceless: years of memories you can read back through, search, and rediscover.
>
> ON THIS DAY
> See what you wrote on today's date one, five, or ten years ago. It's the best part of keeping a journal.
>
> WRITE YOUR WAY
> • Bold, italic, underline, lists and links
> • Add up to 8 photos. Several become a beautiful collage automatically
> • Wrote earlier today? New writing is added to that day's entry
> • Prefer email? Reply to Dabble Me's "How was your day?" email and it becomes an entry too
>
> YEARS OF MEMORIES, ONE TAP AWAY
> • Your whole journal, grouped by month
> • Search every word you've ever written, or tap a #hashtag
> • Random entry: rediscover a moment you'd forgotten
> • Photos full screen with pinch to zoom; save or share the ones you love
> • Comfortable reading with adjustable text size
>
> ASK AI ABOUT YOUR JOURNAL
> Connect Claude or ChatGPT to your journal and ask things like "What made me happiest this year?" or "When did I last go camping?" You approve access, and you can remove it any time.
>
> PRIVATE BY DESIGN
> • No social feed, no ads, no tracking
> • Photo location data is removed before upload
> • Sign in with a passkey, password, or two-factor code
> • Export everything, any time
>
> Writing in the app, search, On This Day, and AI connections are part of Dabble Me PRO.

**Keywords (100)**: these don't repeat words already in the name, which Apple indexes anyway, and use no third-party trademarks (guideline 2.3.7).

```
diary,daily,memories,on this day,reflection,gratitude,photo,writing,mood,notes,ai,life log,email
```

**What's New**: leave blank for 1.0.

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

The app has no analytics or crash SDKs, and these answers match `DabbleMe/Resources/PrivacyInfo.xcprivacy`.

## App Review information

- **Sign-in required:** yes. Create a production demo account (for example `appreview@dabble.me`) on **PRO**, with a few entries that include photos and hashtags, and with password sign-in (no 2FA) so the reviewer can get in.
- **Notes for the reviewer:**

> Dabble Me is a journal people mainly write in by replying to a daily email; the app is its companion for reading and writing entries. Sign in with the demo account above on the sign-in page that opens. Writing, search and On This Day are PRO features; the demo account is PRO. Accounts can be created on the sign-in page and deleted in Settings → Delete Account (we email a link to finish deletion on dabble.me, where it's confirmed with the account password).

- **Export compliance:** the app uses only standard HTTPS (`ITSAppUsesNonExemptEncryption = NO`).

## Screenshots (still to do)

Required sizes: **6.9" iPhone** at 1320 × 2868, plus **13" iPad** at 2064 × 2752 while the app supports iPad. Planned screens, using the made-up demo account only (never a real journal):

1. Journal timeline with photos and month sections
2. An entry with formatting and a collage
3. Writing an entry with the formatting bar and photos
4. On This Day
5. Search results for a #hashtag

`bundle exec rails ios:demo_account` seeds that account locally. It needs valid AWS credentials in `.env` for the photos.

## Open decisions before submitting

- **In-app purchase:** the app currently sells nothing (Apple guideline 3.1.3(f) "free companion" route). Review may still ask for in-app purchase for PRO; see the PR discussion.
- **iPad:** keep it (needs iPad screenshots) or ship iPhone-only for 1.0.
