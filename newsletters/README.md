# Newsletters

The letters Dabble Me sends its subscribers, kept here so they can be read later.

Each newsletter is a folder:

```
newsletters/2026-rewind/
  newsletter.yml   who gets it, and which letter
  rewind.md        one Markdown file per letter
  whats_new.md
```

## newsletter.yml

```yaml
audience: pro          # only PRO accounts, for now
year: 2026             # the year `min_entries_in_year` counts
variants:              # each person gets the first letter they qualify for
  - letter: rewind
    min_entries_in_year: 5
  - letter: whats_new  # the last one has no condition, so everyone gets a letter
```

## A letter

A letter opens with its subject and preview text, then the body in Markdown:

```markdown
---
subject: Your {{year}} Rewind is ready
preview: The line shown after the subject in an inbox.
---

Hi {{first_name}},
```

Placeholders: `{{first_name}}`, `{{year}}`, `{{entry_count}}`, `{{rewind_url}}`, `{{write_url}}`, `{{settings_url}}`. A placeholder nothing fills stops the send. So does the word `TODO` anywhere in a letter, so use it for anything still to fill in.

Every email gets a footer with an unsubscribe link, a link to email settings, and the postal address from `MAILING_ADDRESS`.

## Sending

```bash
# Email yourself every letter, filled in with your own account.
rake 'newsletter:preview[2026-rewind,you@example.com]'

# See how many people would get each letter. Sends nothing.
rake 'newsletter:send[2026-rewind]'

# Send. PER_MINUTE sets the pace (default 120).
SEND=yes rake 'newsletter:send[2026-rewind]'
```

It goes to PRO accounts that haven't turned off "Send me updates about Dabble Me". Each person is sent a newsletter once: running the send again only reaches people it hasn't reached yet.
