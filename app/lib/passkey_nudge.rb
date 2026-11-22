# frozen_string_literal: true

# When the web asks someone to add a passkey (shared/_passkey_nudge): on the journal's pages,
# to an account without one, unless "Not now" was picked in the last SNOOZE_DAYS. After
# MAX_ASKS "Not now"s it stops asking; Account Security still has the button. The cookie holds
# "<times dismissed>:<hidden until, epoch seconds>" and lasts years, so the count survives. It's
# named per account, so one person's "Not now" doesn't quiet it for another on the same browser.
module PasskeyNudge
  COOKIE_PREFIX = 'passkey_nudge'
  SNOOZE_DAYS = 30
  MAX_ASKS = 3
  PAGES = { 'entries' => %w[index today] }.freeze

  module_function

  def show?(user, cookies, controller, action, now: Time.current)
    return false unless user && PAGES.fetch(controller, []).include?(action)

    count, hidden_until = parse(cookies[cookie_name(user)])
    return false if count >= MAX_ASKS || hidden_until > now.to_i

    !user.webauthn_credentials.exists?
  end

  # How many times "Not now" was picked.
  def dismissals(user, cookies)
    parse(cookies[cookie_name(user)]).first
  end

  def cookie_name(user)
    "#{COOKIE_PREFIX}_#{user.id}"
  end

  def parse(value)
    count, hidden_until = value.to_s.split(':', 2).map(&:to_i)
    [count.to_i.clamp(0, MAX_ASKS), hidden_until.to_i]
  end
end
