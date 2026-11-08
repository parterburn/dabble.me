# App Store listing: Dabble Me – Private Journal

Copy for App Store Connect (app ID 6832151292, bundle ID `me.dabble.ios`). Character limits are noted where Apple enforces one. Keep this in sync with what the shipped build actually does.

## App Information

| Field | Value |
|---|---|
| Name (30) | Dabble Me – Private Journal |
| Subtitle (30) | Journal by replying to email |
| Primary category | Lifestyle |
| Secondary category | Productivity |
| Content rights | Does not contain, show, or access third-party content |
| Age rating | 4+ (no objectionable content; entries are private and never shared with other users) |
| Copyright | 2026 Dabble Dev LLC |

## Version 1.0

**Promotional text (170)**

> Your private journal, wherever you are. Read back through years of entries, rediscover what happened on this day, and write with photos when the mood strikes.

**Description (4,000)**

> Dabble Me is a private journal that lives in your email. Pick the days you want a "How was your day?" email, reply to it, and your reply becomes a journal entry, with photos. Every prompt also brings back a random entry from your past, so writing today is a chance to revisit who you were.
>
> The Dabble Me app is the companion to that habit. Read your whole journal, going back years, and write whenever something is worth remembering.
>
> READ BACK THROUGH THE YEARS
> • Your journal, newest first, grouped by month
> • On This Day: see what you wrote on today's date in past years
> • Random entry: rediscover a moment you'd forgotten
> • Photos and collages, full screen with pinch to zoom
> • Tap any #hashtag to find every entry that uses it
>
> WRITE WITH PHOTOS
> • Bold, italic, underline, lists and links
> • Add up to 8 photos. Several become a collage automatically
> • Location data is removed from photos before upload
> • Already wrote today? New writing is added to that day's entry
>
> SEARCH EVERYTHING YOU'VE WRITTEN
> • Find words, exact phrases, or #hashtags across every entry
>
> PRIVATE BY DESIGN
> • No social feed, no sharing, no ads, no tracking
> • Sign in with your passkey, password, or two-factor code
> • Export everything, any time, from dabble.me
>
> Writing in the app, search, and On This Day are part of Dabble Me PRO. Every account can read its journal in the app and write by replying to email.

**Keywords (100)**: these don't repeat words already in the name, which Apple indexes anyway.

```
diary,email,daily,reflection,gratitude,memories,on this day,prompts,writing,mood,notes,life log
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
