# Bugbot rules

Learned rules for parterburn/dabble.me that apply to every reviewed change.

## Logging: user-written text is filtered before it leaves the process

Applies to: `config/initializers/`, `lib/`, `app/controllers/`

Journal text and other user-written fields that are stored encrypted must be named in both `config/initializers/filter_parameter_logging.rb` and `SentrySensitiveScrubber::PRIVATE_CONTENT_KEYS`. Rails logs request parameters, and the scrubber does not consult the Rails filter list, so a key added to only one of them still leaks. Encryption does not help: the plaintext is in the request, before it is saved. `#305` stored `entry_template` encrypted and still would have logged the heading.

# BAD: `encrypts :app_settings` with no `:entry_template` in `filter_parameters` or `PRIVATE_CONTENT_KEYS`
# GOOD: add `:entry_template` to `filter_parameters` and `"entry_template"` to `PRIVATE_CONTENT_KEYS`

Introduced in #305.
