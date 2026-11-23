# Bugbot rules

Learned rules for parterburn/dabble.me that apply when a reviewed change is under `config/initializers/`.

## Auth: signing in cancels a scheduled account deletion

Applies to: `app/controllers/`, `config/initializers/`

DeleteUserJob destroys the account an hour after `deleted_at` is set, unless a sign-in clears it. Password sign-in runs a Warden strategy and sets event `:authentication`. `sign_in` (email-code sign-in, passkey sign-in, and the authenticator page after either) sets event `:set_user`. `Warden::Manager.after_authentication` is only the `:authentication` event, so those sign-ins leave `deleted_at` set and the job still deletes the journal. Session loads are event `:fetch` and must not clear a deletion: the person has not signed in again.

# BAD: `Warden::Manager.after_authentication { |user, _, _| user.cancel_pending_deletion! }`
# GOOD: `Warden::Manager.after_set_user except: :fetch { |user, _, _| user.cancel_pending_deletion! }`

Production bug, introduced in #367.

## Billing: handing a lapsed web plan to Apple must not pass through Free

Applies to: `app/models/`, `app/workers/`, `config/initializers/`

`User#resume_apple_subscription` runs after a save that leaves the plan Free while an App Store subscription still entitles PRO. Writing Free first runs the downgrade callbacks in that same save: MCP tokens are revoked, email days collapse to Sunday, and the Apple plan that follows is treated as a new upgrade (`send_upgrade_email!`). When the previous plan was already PRO, set the Apple plan without those side effects. A real upgrade from Free still goes through `AppStore::Entitlement.sync!`.

# BAD: `user.update(plan: "Free")` so `resume_apple_subscription` can put the Apple plan back, with the downgrade callbacks left on
# GOOD: skip the token revoke and the Sunday-only frequency cut when an Apple subscription still entitles, and set that plan without `send_upgrade_email!` when the previous plan was PRO

Introduced in #332.
