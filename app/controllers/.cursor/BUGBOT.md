# Bugbot rules

Learned rules for parterburn/dabble.me that apply when a reviewed change is under `app/controllers/`.

## Auth: signing in cancels a scheduled account deletion

Applies to: `app/controllers/`, `config/initializers/`

DeleteUserJob destroys the account an hour after `deleted_at` is set, unless a sign-in clears it. Password sign-in runs a Warden strategy and sets event `:authentication`. `sign_in` (email-code sign-in, passkey sign-in, and the authenticator page after either) sets event `:set_user`. `Warden::Manager.after_authentication` is only the `:authentication` event, so those sign-ins leave `deleted_at` set and the job still deletes the journal. Session loads are event `:fetch` and must not clear a deletion: the person has not signed in again.

# BAD: `Warden::Manager.after_authentication { |user, _, _| user.cancel_pending_deletion! }`
# GOOD: `Warden::Manager.after_set_user except: :fetch { |user, _, _| user.cancel_pending_deletion! }`

Production bug, introduced in #367.

## Auth: an emailed confirmation code stands in for the password only when there is none

Applies to: `app/controllers/`

`EmailCode` purpose `"confirm"` proves the inbox for an account with no password (`has_password?` is false). The web already ignores it when the account has a password (`current_password_or_code_valid?`). The API has to make the same check before `EmailCode.confirm`, which consumes the code. A bearer token plus that code must not delete the account or register a passkey. A passkey added that way signs in later with no password and no authenticator code, including after the token is revoked. Accounts with a password confirm with the password or with one of their passkeys.

# BAD: `EmailCode.confirm(current_user, params[:email_code])` whenever `email_code` is present
# GOOD: `params[:email_code].present? && !current_user.has_password? && EmailCode.confirm(current_user, params[:email_code])`

Introduced in #367.
