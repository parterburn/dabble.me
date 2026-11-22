# A six-digit code emailed to an address, entered to prove the person can read that inbox.
#
# - purpose "sign_in": passwordless sign-in and sign-up (EmailSignIn). The address may have no
#   account; one is made only once its code is entered, so a mistyped address leaves nothing.
# - purpose "confirm": a signed-in account with no password confirms a change that would
#   otherwise take the password (deleting the account, adding a passkey, changing the email or
#   setting a password). Tied to the account as well as its address.
#
# Codes last LIFETIME and work once. A resend doesn't void the code before it (mail can arrive
# out of order): the LIVE_CODES newest still-unused codes all work, and the first one entered
# voids the rest. Each wrong guess counts against every live code, which stop at MAX_ATTEMPTS;
# an address stops taking guesses after DAILY_FAILURES in a day, and gets at most
# SENDS_PER_HOUR codes an hour, one per RESEND_AFTER. Rack::Attack also limits by IP.
#
# Only keyed digests are stored, never the code or the address.
class EmailCode < ActiveRecord::Base
  PURPOSES = %w[sign_in confirm].freeze
  LIFETIME = 10.minutes
  LIVE_CODES = 3
  MAX_ATTEMPTS = 5
  DAILY_FAILURES = 20
  SENDS_PER_HOUR = 5
  RESEND_AFTER = 30.seconds
  # Kept a little past a day so DAILY_FAILURES can count them (EmailCodeCleanupWorker).
  KEEP_FOR = 2.days
  LENGTH = 6

  belongs_to :user, optional: true

  validates :purpose, inclusion: { in: PURPOSES }

  scope :for_address, ->(email, purpose) { where(email_digest: email_digest(email), purpose: purpose) }

  class << self
    def normalize(email)
      email.to_s.strip.downcase
    end

    # :ok, :too_soon (within RESEND_AFTER of the last one) or :too_many (SENDS_PER_HOUR).
    def send_status(email, purpose:)
      recent = for_address(email, purpose).where(created_at: 1.hour.ago..)
      return :too_many if recent.count >= SENDS_PER_HOUR
      return :too_soon if recent.exists?(created_at: RESEND_AFTER.ago..)

      :ok
    end

    # Stores a new code for this address and returns it, to be emailed. Check send_status first.
    def issue!(email, purpose:, user: nil)
      code = SecureRandom.random_number(10**LENGTH).to_s.rjust(LENGTH, '0')
      create!(purpose: purpose, email_digest: email_digest(email), user: user,
              code_digest: code_digest(email, purpose, code), expires_at: LIFETIME.from_now)
      code
    end

    # The live code this matches, or nil (and the guess is counted). Doesn't use it up: call
    # #use! once everything else about the request has checked out (a 2FA code, say).
    def match(email, code, purpose:, user: nil)
      live = live_codes(email, purpose, user)
      return if live.empty?

      digits = code.to_s.gsub(/\D/, '')
      if digits.length == LENGTH
        wanted = code_digest(email, purpose, digits)
        found = live.find { |c| ActiveSupport::SecurityUtils.secure_compare(c.code_digest, wanted) }
        return found if found
      end

      where(id: live.map(&:id)).update_all('attempts = attempts + 1')
      nil
    end

    # match, then use!: true once for a right code.
    def redeem(email, code, purpose:, user: nil)
      !!match(email, code, purpose: purpose, user: user)&.use!
    end

    # Emails a "confirm" code to a signed-in account (one with no password confirms changes with
    # it). Returns send_status: the code went out only for :ok.
    def send_confirmation(user)
      status = send_status(user.email, purpose: 'confirm')
      return status unless status == :ok

      UserMailer.confirmation_code(user, issue!(user.email, purpose: 'confirm', user: user)).deliver_later
      :ok
    end

    # True once for a right "confirm" code sent to this account.
    def confirm(user, code)
      code.present? && redeem(user.email, code, purpose: 'confirm', user: user)
    end

    def cleanup!
      where(created_at: ...KEEP_FOR.ago).delete_all
    end

    def email_digest(email)
      OpenSSL::HMAC.hexdigest('SHA256', secret, "email:#{normalize(email)}")
    end

    private

    def live_codes(email, purpose, user)
      scope = for_address(email, purpose)
      scope = scope.where(user_id: user.id) if user
      return none if scope.where(created_at: 1.day.ago..).sum(:attempts) >= DAILY_FAILURES

      scope.where(used_at: nil, expires_at: Time.current..).where(attempts: ...MAX_ATTEMPTS)
           .order(created_at: :desc).limit(LIVE_CODES).to_a
    end

    def code_digest(email, purpose, code)
      OpenSSL::HMAC.hexdigest('SHA256', secret, "code:#{purpose}:#{normalize(email)}:#{code}")
    end

    def secret
      @secret ||= Rails.application.key_generator.generate_key('email_code', 32)
    end
  end

  # A wrong guess at something this code unlocks (the account's 2FA code after it).
  def count_failed_attempt!
    self.class.where(id: id).update_all('attempts = attempts + 1')
  end

  # Marks this code used, and voids the address's other codes for the same purpose. False when
  # another request used it first.
  def use!
    now = Time.current
    return false unless self.class.where(id: id, used_at: nil).update_all(used_at: now) == 1

    self.class.where(email_digest: email_digest, purpose: purpose, used_at: nil).update_all(used_at: now)
    true
  end
end
