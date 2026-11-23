# frozen_string_literal: true

# The page after a web sign-in that asks an account with no passkey to add one
# (Passkeys::OffersController). It shows once per account per browser: showing it sets a
# long-lived cookie named for the account, so another person's visit on the same browser
# doesn't quiet it for them, and it never shows again on that browser whatever they picked.
#
# Not shown after sign-up, to admins (AdminAccess makes them add one), or when the sign-in is on
# its way somewhere that shouldn't be interrupted: connecting an app (OAuth), a gift link, or
# the passkey pages themselves. Account Security keeps its Add Passkey button for later.
# The iOS app asks in its own way after a password sign-in (PasskeyPrompt.swift).
module PasskeyOffer
  COOKIE_PREFIX = 'passkey_offered'
  RETURN_TO = :passkey_offer_return_to
  # Destinations a sign-in heads to without a stop on the way.
  SKIP_PATHS = %r{\A/(oauth|gift|passkeys|security)(/|\z|\?)}

  module_function

  def offer?(user, cookies, destination)
    return false unless user.is_a?(User)
    return false if cookies[cookie_name(user)].present?
    return false if AdminAccess.passkey_required?(user)
    return false if destination.to_s.match?(SKIP_PATHS)

    !user.webauthn_credentials.exists?
  end

  def offered!(user, cookies, secure:)
    cookies[cookie_name(user)] = {
      value: Time.current.to_i.to_s, expires: 10.years.from_now, httponly: true,
      same_site: :lax, secure: secure
    }
  end

  def cookie_name(user)
    "#{COOKIE_PREFIX}_#{user.id}"
  end

  # A local path to continue to, never another site.
  def safe_path(path)
    path = path.to_s
    path.start_with?('/') && !path.start_with?('//', '/\\') ? path : nil
  end
end
