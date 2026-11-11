# Recap page design

One self-contained HTML page (or the host's HTML artifact): a phone-shaped story deck the user taps through, like Spotify Wrapped. No external scripts or frameworks. Fonts may load from Google Fonts; everything else is inline.

## Look

- **Fonts:** Bricolage Grotesque (400, 600, 800) for everything; Newsreader italic for quotes and saved letters. Fall back to the system sans and Georgia.
- **Slide colors** (background / text):
  - olive `#5E6B23` / `#F6F5EE`
  - moss `#1C230F` / `#F6F5EE`
  - plum `#3A1D38` / `#F6F5EE`
  - saffron `#F0B429` / `#1C230F`
  - sage `#DCE4C6` / `#1C230F`
  - sky `#BCD6E3` / `#1C230F`
  - Page behind the deck: `#0F1408`. In dark mode, darken olive to `#4C581C`, saffron to `#D99F1E`, sage to `#C9D2B0`, sky to `#A6C3D1`, and the page to `#080B04`.
- **Type:** headings weight 800, tight tracking (about -0.035em), line height about 0.92. Slide titles about 2.1–2.9rem, the cover title 3–4.6rem, and the "huge" stat numbers 7–11rem. Body copy about 1.06rem with a line length of about 34 characters.
- **Photos:** rounded 6px corners, a soft shadow, and a slight tilt (about -1.5° or 1.2°). One photo shows large at 4:3; two or four sit in a strip of 3:4 tiles; three form a collage with the first spanning two rows.

## Stage and navigation

- The deck is centered, up to 460 × 860 px, filling a phone screen edge to edge and rounding its corners (22px) on wider screens. It respects safe-area insets.
- Only one slide shows at a time and slides cross-fade in about 0.35s. Content is vertically centered with about 64px top padding, 28px sides, and 92px bottom (clear of the buttons).
- Progress bars along the top, one per slide, 3px tall; bars up to the current slide are bright, the rest faint. They and the buttons take the current slide's text color.
- Back and Next pill buttons at the bottom; Back is disabled on the first slide, Next on the last. Tapping the left third goes back and the right two thirds goes forward. Arrow keys and the space bar also navigate.
- A visually hidden live region announces "Slide N of M: <title>". The deck is labeled as a carousel. Honor `prefers-reduced-motion`: no fades or typing animation.

## Slides, in order

1. **Cover** (olive): a mosaic of every photo filling the slide behind an olive gradient veil, then "Dabble Me · <date range>", the title (default "<year>, as you wrote it."), "<N> entries, read front to back. Here's what you kept coming back to.", and "Tap or press → to start".
2. **Count** (saffron): the entry count as a huge number, "times you showed up.", then distinct days, total words of their own, average words per entry, and entries with photos. Mention any entries saved from someone else.
3. **Photo wall** (moss), only with four or more photos: "<N> entries came with pictures." and a 4-column grid of square crops.
4. **Months** (moss): "<Month> was your loudest month.", its count, and any months with no entries. A bar chart with one bar per month in the period, labeled with the month's initial and count; the top month's bar is saffron and empty months are faint. Up to four photos from the top month below.
5. **Weekdays** (sky): "You're a weekend writer." when at least half the entries fall on Saturday or Sunday, otherwise "<Weekday>s were your day.", with the count. The same bar chart Sunday through Saturday, plus up to four weekend photos.
6. **Longest and shortest** (moss): two columns, each with the date, the word count as a big number, and that day's photo if it has one; the shortest entry quoted underneath in Newsreader italic (trimmed to about 220 characters).
7. **Narrative cards**, which you write (see below), cycling saffron, moss, sky, plum, sage, olive unless a color suits the card better.
8. **Index** (sage, scrolls): "All <N>, in order." and "Scroll this one. Dates open the entry in Dabble Me." Every entry newest first: a 52px thumbnail (or a dashed empty square), the date linked to `https://dabble.me/entries/YYYY/M/D`, and a one-line summary. Tap navigation is off on this slide so it can scroll.
9. **Close** (olive): the latest photo (tall, tilted), "Word of the year", the word large, one sentence on why, and a saffron pill button "Write today's entry" linking to https://dabble.me/write.

## Narrative card types

Each card has a title, an optional subtitle, and one body type. Keep each readable on a phone without scrolling: about 5 items or 70 words. Every card except quotes should carry at least one photo when the relevant entries have them.

- **Ranked list:** numbered rows of label and value, each with a 48px round photo when there is one, divided by faint rules. Top cast, top places.
- **Timeline:** a vertical line with dots; each item has a small date, a sentence, and an optional 64px photo on the right. Wins, a thread over time, a project.
- **Facts:** short rows divided by faint rules, then photos. The hardest stretch, family, outings.
- **Quotes:** 4–6 of the user's own sentences in Newsreader italic, each with its date below, typed out one character at a time with a blinking caret when the slide opens (about 38ms per character, a short pause between lines).
- **Chips:** outlined pill labels, then photos. Costumes, places, songs, foods.
- **Text:** paragraphs, optionally led by a saved letter or quote in Newsreader. "What the journal missed", letters they saved.

Order the narrative cards as a story: people, places, standout moments, lines of the year, wins, themes, the hard stretch, what the journal missed.

## Building it safely

- Escape all entry text before putting it in the page. Allow only `<strong>` and `<em>` in text you write.
- Show photos from each entry's `image_url`. If the host blocks remote images or a photo fails to load, leave it out rather than showing a broken image, and tell the user which dates are missing photos.
