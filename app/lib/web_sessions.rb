# frozen_string_literal: true

# Web sign-ins as UserSession rows (Warden hooks in config/initializers/user_sessions.rb).
#
# A sign-in makes a row and a random token. The token goes in the Rails session (so the browser's
# session cookie names its row) and in an encrypted device cookie that lasts as long as "Stay
# logged in" (so a remembered browser coming back names its row too). On every request the row
# must still exist: signing a session out deletes it, and that browser is signed out on its next
# request, even if it holds a copy of its old cookies.
#
# Browsers signed in before this shipped have no token. Their session is given a row the first
# time it's seen, until LEGACY_SESSIONS_UNTIL; their "Stay logged in" cookie is given one when
# it was made before TRACKING_STARTED_AT. Sign out of all devices (User#sign_out_everywhere!)
# ends those too, by changing the salt Devise checks.
module WebSessions
  SESSION_KEY = 'user_session_token'
  DEVICE_COOKIE = :_dabbleme_device
  TRACKING_STARTED_AT = Time.utc(2026, 11, 23)
  # Browsers keep session cookies for as long as they stay open, so this is generous.
  LEGACY_SESSION_GRACE = 30.days

  module_function

  # A sign-in (password, passkey, emailed code, sign-up) or "Stay logged in" bringing one back.
  def signed_in(user, warden, options)
    return unless tracked?(user, options) && options[:store] != false

    request = ActionDispatch::Request.new(warden.env)
    device_token = request.cookie_jar.encrypted[DEVICE_COOKIE]
    session = UserSession.web.find_by_token(device_token)
    session = nil unless session&.user_id == user.id

    if remembered?(warden) && session.nil? && !legacy_remember_cookie?(warden, device_token)
      # This browser's row was signed out (or never made): its "Stay logged in" cookie no longer
      # counts. Devise's logout hook deletes that cookie.
      warden.logout(options[:scope])
      return
    end

    if session
      session.touch_activity!(request)
      token = device_token
    else
      session, token = UserSession.start!(user, kind: 'web', request: request)
    end
    store(warden, options[:scope], request, session, token)
  end

  # Every request from a signed-in browser.
  def fetched(user, warden, options)
    return unless tracked?(user, options)

    request = ActionDispatch::Request.new(warden.env)
    token = scoped_session(warden, options[:scope])[SESSION_KEY]
    session = UserSession.web.find_by_token(token) if token

    if session&.user_id == user.id
      session.touch_activity!(request)
      Current.user_session = session
    elsif (token.nil? || session) && legacy_sessions_allowed?
      # No token, or another account's (a session switched accounts without a sign-in, which
      # only test helpers do): handled like a browser from before sessions were tracked.
      session, token = UserSession.start!(user, kind: 'web', request: request)
      store(warden, options[:scope], request, session, token)
    else
      warden.logout(options[:scope])
    end
  end

  # Sign Out on this browser: its row goes, so copies of its cookies stop working too.
  def signing_out(user, warden, options)
    return unless tracked?(user, options)

    token = scoped_session(warden, options[:scope])[SESSION_KEY]
    session = UserSession.web.find_by_token(token)
    session.destroy if session&.user_id == user.id
    ActionDispatch::Request.new(warden.env).cookie_jar.delete(DEVICE_COOKIE)
    Current.user_session = nil
  end

  def tracked?(user, options)
    options[:scope] == :user && user.is_a?(User) && user.persisted?
  end

  def store(warden, scope, request, session, token)
    warden.raw_session["warden.user.#{scope}.session"] ||= {}
    scoped_session(warden, scope)[SESSION_KEY] = token
    request.cookie_jar.encrypted[DEVICE_COOKIE] = {
      value: token, expires: Devise.remember_for.from_now, httponly: true, same_site: :lax,
      secure: Rails.env.production?
    }
    Current.user_session = session
  end

  # Warden's per-scope session hash, read directly: warden.session(scope) looks the user up
  # again, which during logout (the user already unset) would run these hooks once more.
  def scoped_session(warden, scope)
    warden.raw_session["warden.user.#{scope}.session"] || {}
  end

  def remembered?(warden)
    warden.winning_strategy.is_a?(Devise::Strategies::Rememberable)
  end

  # A "Stay logged in" cookie from before sessions were tracked, from a browser that never had a
  # device cookie. Devise's cookie holds the time it was written.
  def legacy_remember_cookie?(warden, device_token)
    return false if device_token.present?

    written_at = Array(warden.winning_strategy.send(:remember_cookie))[2].to_f
    written_at.positive? && Time.at(written_at).utc < TRACKING_STARTED_AT
  end

  def legacy_sessions_allowed?
    Time.current < legacy_sessions_until
  end

  def legacy_sessions_until
    Rails.application.config.x.legacy_web_sessions_until || (TRACKING_STARTED_AT + LEGACY_SESSION_GRACE)
  end
end
