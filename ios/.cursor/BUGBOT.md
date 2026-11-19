# Bugbot rules

Learned rules for parterburn/dabble.me that apply when a reviewed change is under `ios/`.

## API: JSON null is omitted, not a value, on a partial update

Applies to: `app/controllers/api/v1/`, `ios/`

A PATCH that changes one field must leave the others as they are. Swift's synthesized `Encodable` writes a nil optional as JSON `null`, and `params.key?` is true for that key, so a null is easy to mistake for "the client sent this." `#305` mapped a null `entry_template` to `[]`, a null `entry_template_auto` to false, and rejected a null `widget_content`. The iOS app sends one account setting at a time and leaves the others nil, so a widget change erased the template and a template change never saved. Ignore null (treat the key as absent). An emptied template is `[]`. A switch that is off is `false`, not null. On the client, encode with `encodeIfPresent` so an unset field is left out of the body.

# BAD: `settings['entry_template'] = [] if params[:entry_template].nil?`
# GOOD: `return unless params.key?(key) && !params[key].nil?`

Introduced in #305.
