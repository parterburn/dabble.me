# frozen_string_literal: true

# Admin accounts must confirm a passkey before their session can be used, and
# again every PASSKEY_FRESHNESS. A password, a two-factor code, a "Stay logged
# in" cookie or a trusted-browser cookie alone never reaches an admin session.
#
# The proof lives in the session as [user id, unix time]. Tying it to the user
# id keeps one account's check from vouching for another in the same browser.
#
# An admin who has lost every passkey is recovered from the Rails console, e.g.
# by registering a new one, or by turning `admin` off and back on afterwards.
module AdminAccess
  PASSKEY_FRESHNESS = 12.hours
  SESSION_KEY = "admin_passkey_verified"
  RETURN_TO_KEY = "admin_passkey_return_to"

  module_function

  def passkey_required?(user)
    user.present? && user.admin?
  end

  def record_passkey!(session, user)
    session[SESSION_KEY] = [user.id, Time.current.to_i]
  end

  def passkey_fresh?(session, user)
    user_id, verified_at = session[SESSION_KEY]
    user_id == user.id && verified_at.is_a?(Integer) && Time.at(verified_at) > PASSKEY_FRESHNESS.ago
  end

  # Where to go after the passkey check. Only same-site paths are kept.
  def remember_return_to!(session, path)
    session[RETURN_TO_KEY] = path if safe_path?(path)
  end

  def take_return_to!(session)
    path = session.delete(RETURN_TO_KEY)
    safe_path?(path) ? path : nil
  end

  def safe_path?(path)
    path.is_a?(String) && path.start_with?("/") && !path.start_with?("//") && !path.include?("\\")
  end
end
