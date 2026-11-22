# A device signed in to an account: a web browser (WebSessions, through Devise/Warden) or the
# iOS app (AppSessions, through its OAuth tokens). Listed under Sessions on Account Security,
# where each can be signed out.
#
# Kept small for privacy: a browser/OS label, a coarse place from Cloudflare's visitor-location
# headers (never the IP address), and when it was last used. Only the latest place is kept.
# UserSessionCleanupWorker deletes rows that can no longer sign anything in.
class UserSession < ActiveRecord::Base
  KINDS = %w[web ios_app].freeze
  # How often a session's last-active time (and place) is written, at most.
  ACTIVITY_INTERVAL = 10.minutes
  # The app's device header (X-Dabble-Device) must be one of these.
  APP_DEVICES = %w[iPhone iPad Mac].freeze

  belongs_to :user

  validates :kind, inclusion: { in: KINDS }

  scope :web, -> { where(kind: 'web') }
  scope :ios_app, -> { where(kind: 'ios_app') }
  scope :most_recent_first, -> { order(last_active_at: :desc, id: :desc) }
  # The app's sessions that still hold a live token, plus every web session. An app that signed
  # out by revoking its token (/oauth/revoke) has nothing left to sign in with.
  scope :listable, lambda {
    live_tokens = Doorkeeper::AccessToken.where(revoked_at: nil)
                                         .where('oauth_access_tokens.user_session_id = user_sessions.id')
    where(kind: 'web').or(where(kind: 'ios_app').where(live_tokens.arel.exists))
  }

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token.to_s)
  end

  def self.new_token
    SecureRandom.urlsafe_base64(32)
  end

  def self.find_by_token(token)
    return if token.blank?

    find_by(token_digest: digest(token))
  end

  # A new row for a sign-in from this request. Web sessions get a token (returned with it).
  def self.start!(user, kind:, request:)
    token = kind == 'web' ? new_token : nil
    session = user.user_sessions.create!(kind: kind, token_digest: token && digest(token),
                                         last_active_at: Time.current, **details_from(request, kind))
    [session, token]
  end

  # What's shown for a device: its browser and OS (or app device) and Cloudflare's guess at where
  # the request came from. Cloudflare adds CF-IPCountry by default and the city and region with
  # its "Add visitor location headers" managed transform; without them the place is blank.
  def self.details_from(request, kind)
    headers = request.headers
    label = if kind == 'ios_app'
              { browser: 'Dabble Me app', os: app_device(headers['X-Dabble-Device']) }
            else
              UserAgentLabel.parse(request.user_agent)
            end
    label.merge(city: header_text(headers['CF-IPCity']),
                region: header_text(headers['CF-Region']),
                country: country_code(headers['CF-IPCountry']))
  end

  def self.app_device(value)
    APP_DEVICES.find { |device| device == value.to_s.strip } || 'iPhone'
  end

  def self.header_text(value)
    text = value.to_s.dup.force_encoding(Encoding::UTF_8).scrub('').strip
    text.presence&.first(80)
  end

  # Two letters, but not Cloudflare's XX (unknown) or T1 (Tor).
  def self.country_code(value)
    code = value.to_s.strip.upcase
    code if code.match?(/\A[A-Z]{2}\z/) && !%w[XX T1].include?(code)
  end

  # Called on each request the session makes; writes at most every ACTIVITY_INTERVAL.
  def touch_activity!(request)
    return if last_active_at && last_active_at > ACTIVITY_INTERVAL.ago

    update_columns(last_active_at: Time.current, updated_at: Time.current,
                   **self.class.details_from(request, kind).slice(:city, :region, :country))
  end

  def web?
    kind == 'web'
  end

  def app?
    kind == 'ios_app'
  end

  # Signs this device out: the app's tokens stop working at once; a browser is turned away on its
  # next request, because its session and "Stay logged in" cookies point to this row (WebSessions).
  def revoke!
    Doorkeeper::AccessToken.where(user_session_id: id, revoked_at: nil).update_all(revoked_at: Time.current)
    destroy!
  end

  def device_label
    app? ? "Dabble Me app on #{os}" : [browser, os].compact_blank.join(' on ')
  end

  def location_label
    [city, region, country].compact_blank.uniq.join(', ').presence
  end
end
