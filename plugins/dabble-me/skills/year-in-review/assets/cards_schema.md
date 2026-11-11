# cards.json

```json
{
  "word": "Repair.",
  "word_note": "One sentence on why, from the entries.",
  "summaries": { "<entry id>": "One line, specific, in plain words." },
  "cards": [ <card>, ... ]
}
```

`img` / `imgs` values are entry dates (YYYY-MM-DD) whose entry has a photo. Text fields accept `<strong>` and `<em>`; everything else is escaped.

| type | fields | use for |
|---|---|---|
| `rank` | `title`, `items[{label, value, img?}]`, `note?` | top cast, top places |
| `timeline` | `title`, `subtitle?`, `items[{when, text, img?}]`, `note?` | wins, a thread over time, a project |
| `facts` | `title`, `subtitle?`, `items[html]`, `imgs?`, `note?` | hardest stretch, family, outings |
| `lines` | `title`, `items[{text, when}]` | exact quotes, typed out on screen (4–6) |
| `chips` | `title`, `items[text]`, `imgs?`, `note?` | costumes, places, songs, foods |
| `text` | `title`, `subtitle?`, `body[html paragraphs]`, `imgs?`, `quote?` | letters saved, "what the journal missed" |

Order cards as a story: people, places, standout moments, lines, wins, themes, hard stretch, what was missed. Keep each card readable on a phone without scrolling: about 5 items or 70 words. Every card except `lines` should carry at least one photo when the relevant entries have them.
