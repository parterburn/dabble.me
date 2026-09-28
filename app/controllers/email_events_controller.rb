class EmailEventsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]
  before_action      :authenticate_mailgun_request!, only: [:create]

  def create
    @user = User.where(email: recipient).first
    if @user.present? && event_type.in?(["failed", "complained", "unsubscribed"])
      process_bounce
      return head(200)
    else
      return head(406)
    end
  end

  private

  def event_type
    mailgun_params['event']
  end

  def recipient
    mailgun_params['recipient'].try(:downcase)
  end

  def delivery_status
    mailgun_params['delivery-status'].inspect
  end

  def mailgun_params
    params[:'event-data'].to_unsafe_h
  end

  def process_bounce
    @user.increment(:emails_bounced)
    @user.frequency = [] if @user.is_free? || @user.emails_bounced > 20
    @user.save
  end

  # ========================================
  # AUTHENTICATION
  # ========================================

  # Reject signatures older than Mailgun's webhook retry window (10m, 10m, 15m,
  # 30m, 1h, 2h, 4h ~= 8h10m, plus margin) so late retries still land but a
  # captured payload can't be replayed indefinitely.
  MAX_SIGNATURE_AGE = 9.hours

  def mailgun_auth_params
    params.permit(signature: [:signature, :timestamp, :token])
  end

  def event_params
    mailgun_auth_params[:signature]&.to_h || {}
  end

  def timestamp
    event_params['timestamp'].to_s
  end

  def token
    event_params['token'].to_s
  end

  def actual_signature
    event_params['signature'].to_s
  end

  def fresh_timestamp?
    timestamp.match?(/\A\d+\z/) && (Time.now.to_i - timestamp.to_i).abs <= MAX_SIGNATURE_AGE
  end

  def legit_request?
    signing_key = ENV['MAILGUN_SIGNING_KEY']
    return false if signing_key.blank? || token.blank? || actual_signature.blank? || !fresh_timestamp?

    expected = OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, signing_key, "#{timestamp}#{token}")
    ActiveSupport::SecurityUtils.secure_compare(actual_signature, expected)
  end

  def authenticate_mailgun_request!
    return true if legit_request?

    Sentry.capture_message("Mailgun signature did not match.", level: :info, extra: { timestamp: timestamp, token: token })
    head(:forbidden)
    false
  end
end
