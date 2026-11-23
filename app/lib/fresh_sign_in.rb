# frozen_string_literal: true

# When this browser last signed in by proving who it is: a password, an emailed code, a passkey
# or a 2FA code (a Warden hook in config/initializers/user_sessions.rb). A "Stay logged in"
# cookie bringing a session back doesn't count, and neither does an already signed-in browser
# visiting the sign-in page.
#
# For FRESH_FOR after one, adding a passkey on the web needs nothing more
# (ApplicationController#passkey_proof_needed?), as the iOS app's setup token does after its
# password sign-in. That's what lets the page after sign-in (PasskeyOffer) add one in a tap.
module FreshSignIn
  SESSION_KEY = 'signed_in_at'
  FRESH_FOR = 15.minutes

  module_function

  def record(user, warden, options)
    return unless options[:scope] == :user && user.is_a?(User) && options[:store] != false
    return if warden.winning_strategy.is_a?(Devise::Strategies::Rememberable)

    warden.raw_session[SESSION_KEY] = Time.current.to_i
  end

  def fresh?(session)
    signed_in_at = session[SESSION_KEY]
    signed_in_at.is_a?(Integer) && Time.at(signed_in_at) > FRESH_FOR.ago
  end
end
