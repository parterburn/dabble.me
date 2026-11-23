# frozen_string_literal: true

# Web sign-ins as UserSession rows (Warden hooks in config/initializers/user_sessions.rb).
#
# A sign-in makes a row and a random token. The token goes in the Rails session (so the browser's
# session cookie names its row) and in an encrypted device cookie that lasts as long as Devise's
# remember cookie (so a remembered browser coming back names its row too). Every sign-in is
# remembered (User#remember_me), and both cookies are renewed while the browser is used, so a
# browser stays signed in until it goes Devise.remember_for without a visit. On every request the row
# must still exist: signing a session out deletes it, and that browser is signed out on its next
# request, even if it holds a copy of its old cookies.
#
# Browsers signed in before this shipped have no token. Their session is given a row the first
# time it's seen, until LEGACY_SESSIONS_UNTIL; their remember cookie is given one when
# it was made before TRACKING_STARTED_AT. Sign out of all devices (User#sign_out_everywhere!)
# ends those too, by changing the salt Devise checks.
module WebSessions
  SESSION_KEY = 'user_session_token'
  DEVICE_COOKIE = :_dabbleme_device
  # Tracking went live 2026-11-22 23:21 UTC (PR 369's deploy). Every remember cookie written since
  # came with a device cookie, so one arriving without it is a copy being replayed, not an old
  # browser. (This was 2026-11-24, which let a copied cookie from before then revive a session
  # that had been signed out.)
  TRACKING_STARTED_AT = Time.utc(2026, 11, 23)
  # Browsers keep session cookies for as long as they stay open, so this is generous. Ends
  # 2026-12-24, as it did before TRACKING_STARTED_AT moved back a day.
  LEGACY_SESSION_GRACE = 31.days
  # How often a browser in use gets its remember and device cookies rewritten.
  RENEW_COOKIES_EVERY = 1.day

  module_function

  # A sign-in (password, passkey, emailed code, sign-up) or a remember cookie bringing one back.
  def signed_in(user, warden, options)
    return unless tracked?(user, options) && options[:store] != false

    request = ActionDispatch::Request.new(warden.env)
    device_token = request.cookie_jar.encrypted[DEVICE_COOKIE]
    session = UserSession.web.find_by_token(device_token)
    session = nil unless session&.user_id == user.id

    if remembered?(warden) && session.nil? && !legacy_remember_cookie?(warden, device_token)
      # This browser's row was signed out (or never made): its remember cookie no longer
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
      keep_remembered(user, warden, request, token)
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
    write_device_cookie(request, token)
    Current.user_session = session
  end

  def write_device_cookie(request, token)
    request.cookie_jar.encrypted[DEVICE_COOKIE] = {
      value: token, expires: Devise.remember_for.from_now, httponly: true, same_site: :lax,
      secure: Rails.env.production?
    }
  end

  # Devise renews its remember cookie only when the cookie signs a browser back in, so a browser
  # that keeps its session cookie would see the cookie run out 30 days after sign-in however often
  # it's used. Rewriting both cookies (at most daily) makes the 30 days count from the last visit.
  # Only on page loads: JSON and other public, cacheable responses never carry these cookies.
  def keep_remembered(user, warden, request, token)
    return unless request.get? && request.format.html?

    # A cookie that no longer passes (a password change moved the salt) is rewritten right away.
    id, salt, generated_at = request.cookie_jar.signed[remember_cookie_key(user)]
    valid = Array(id) == user.to_key && user.remember_me?(salt, generated_at)
    return if valid && Time.at(generated_at.to_f) > RENEW_COOKIES_EVERY.ago

    ensure_remember_created_at(user)
    Devise::Hooks::Proxy.new(warden).remember_me(user)
    write_device_cookie(request, token)
  end

  # Devise's remember_me! fills in remember_created_at with a full save (every User callback) and
  # only accepts cookies written after it. Two tabs both seeing it unset could each save their own
  # time, leaving the earlier tab's new cookie dead. Set it once, in SQL, and use whichever won.
  def ensure_remember_created_at(user)
    return if user.remember_created_at

    User.where(id: user.id, remember_created_at: nil).update_all(remember_created_at: Time.current)
    # write_attribute + clear: the in-memory user matches the row, so remember_me! has nothing to save.
    user.remember_created_at = User.where(id: user.id).pick(:remember_created_at)
    user.clear_attribute_changes([:remember_created_at])
  end

  def remember_cookie_key(user)
    user.rememberable_options.fetch(:key, 'remember_user_token')
  end

  # Warden's per-scope session hash, read directly: warden.session(scope) looks the user up
  # again, which during logout (the user already unset) would run these hooks once more.
  def scoped_session(warden, scope)
    warden.raw_session["warden.user.#{scope}.session"] || {}
  end

  def remembered?(warden)
    warden.winning_strategy.is_a?(Devise::Strategies::Rememberable)
  end

  # A remember cookie from before sessions were tracked, from a browser that never had a
  # device cookie. Devise's cookie holds the time it was written.
  def legacy_remember_cookie?(warden, device_token)
    return false if device_token.present?

    written_at = Array(warden.winning_strategy.send(:remember_cookie))[2].to_f
    written_at.positive? && Time.at(written_at).utc < TRACKING_STARTED_AT
  end

  def legacy_sessions_allowed?
    Time.current < legacy_sessions_until
  end

  # config.x returns an empty ActiveSupport::OrderedOptions (truthy) for a key nobody set, so only
  # a real time counts as an override. Production sets none.
  def legacy_sessions_until
    override = Rails.application.config.x.legacy_web_sessions_until
    override.is_a?(Time) ? override : TRACKING_STARTED_AT + LEGACY_SESSION_GRACE
  end
end
