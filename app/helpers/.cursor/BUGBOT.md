# Bugbot rules

Learned rules for parterburn/dabble.me that apply when a reviewed change is under `app/helpers/`.

## Entries: a remote image in the body is not rendered or exported as an image

Applies to: `app/helpers/`, `app/services/`, `app/lib/`

An entry's photo is `entry.image`. An `<img>` in the body (a plain-text email, or HTML pasted into the editor) is loaded from someone else's server when that HTML is shown. `ReverseMarkdown` turns the same tag into `![](url)`, and a Markdown preview loads that too. `format_body`, the HTML export, and the Markdown export all drop body images. The entry's own photo is added beside the body. Do not put `img` or `src` back on those allow lists, and do not pass the raw body to `ReverseMarkdown`.

# BAD: `sanitize body, tags: %w(img), attributes: %w(src)` or `ReverseMarkdown.convert(entry.formatted_body)`
# GOOD: leave `img` off the allow list, and strip `<img>` before `ReverseMarkdown`

Introduced in #395.
