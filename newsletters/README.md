# Newsletters

The letters Dabble Me sends its subscribers, kept here so they can be read later.

Each newsletter is a folder:

```
newsletters/2026-rewind/
  newsletter.yml   who gets it, and the variants of the letter
  letter.md        the letter
```

## newsletter.yml

```yaml
year: 2026             # the year `min_entries_in_year` counts

audiences:             # who it goes to: pro, free, or both
  pro: {}
  free:
    from: "Paul from Dabble Me <hello@updates.dabble.me>"
    reply_to: hello@dabble.me
    mailgun_domain: updates.dabble.me
    active_within_months: 18

variants:              # each person gets the first variant for their plan they qualify for
  - name: rewind
    plan: pro
    min_entries_in_year: 5
  - name: whats_new    # a plan's last variant has no condition, so everyone on it gets a letter
    plan: pro
  - name: rewind_free
    plan: free
    min_entries_in_year: 5
  - name: whats_new_free
    plan: free
```

Who is in each audience:

- **pro**: PRO accounts that haven't turned off "Send me updates about Dabble Me".
- **free**: free accounts that haven't turned updates off, have never bounced an email, and (with `active_within_months`) signed in or wrote an entry that recently.

An audience can set `from`, `reply_to` and `mailgun_domain` to send from its own address and Mailgun domain. Without them it uses the app's.

## letter.md

Everyone gets the same letter, apart from the parts marked for one variant. It opens with the subject and preview text, then the body in Markdown:

```markdown
---
subject:
  rewind: Your {{year}} Rewind is ready
  whats_new: What's new in Dabble Me
preview: The line shown after the subject in an inbox.
---

Hi {{first_name}},

{{#rewind}}
You wrote {{entry_count}} entries in {{year}}.

{{/rewind}}
Here is what's new.
```

- **Subject and preview** are one line for everyone, or one line per variant.
- **A block** between `{{#rewind}}` and `{{/rewind}}`, each on a line of its own, appears only in the `rewind` variant. `{{#rewind,rewind_free}}` appears in either.
- **Placeholders** are filled in per person: `{{first_name}}`, `{{year}}`, `{{entry_count}}`, `{{rewind_url}}`, `{{write_url}}`, `{{subscribe_url}}`, `{{settings_url}}`.

A placeholder nothing fills, a block naming no variant, or a subject missing a variant stops the letter loading, and a spec loads every letter. The word `TODO` anywhere in a letter stops the send, so use it for anything still to fill in.

Every email gets a footer with an unsubscribe link, a link to email settings, and the postal address from `MAILING_ADDRESS`.

## Sending

```bash
# Email yourself every variant, filled in with your own account.
rake 'newsletter:preview[2026-rewind,you@example.com]'

# See how many people would get each variant. Sends nothing.
rake 'newsletter:send[2026-rewind]'

# Send. PER_MINUTE sets the pace (default 120).
SEND=yes rake 'newsletter:send[2026-rewind]'

# One plan at a time, and at most 300 emails this run.
SEND=yes PLAN=free LIMIT=300 rake 'newsletter:send[2026-rewind]'
```

Each person is sent a newsletter once: running the send again only reaches people it hasn't reached yet. That is how to build up a new sending domain: send to a few hundred with `LIMIT`, check bounces and complaints in Mailgun, then run it again the next day with a larger limit.
