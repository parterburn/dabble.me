# Bugbot rules

Learned rules for parterburn/dabble.me that apply when a reviewed change is under `app/models/`.

## Billing: handing a lapsed web plan to Apple must not pass through Free

Applies to: `app/models/`, `app/workers/`, `config/initializers/`

`User#resume_apple_subscription` runs after a save that leaves the plan Free while an App Store subscription still entitles PRO. Writing Free first runs the downgrade callbacks in that same save: MCP tokens are revoked, email days collapse to Sunday, and the Apple plan that follows is treated as a new upgrade (`send_upgrade_email!`). When the previous plan was already PRO, set the Apple plan without those side effects. A real upgrade from Free still goes through `AppStore::Entitlement.sync!`.

# BAD: `user.update(plan: "Free")` so `resume_apple_subscription` can put the Apple plan back, with the downgrade callbacks left on
# GOOD: skip the token revoke and the Sunday-only frequency cut when an Apple subscription still entitles, and set that plan without `send_upgrade_email!` when the previous plan was PRO

Introduced in #332.
