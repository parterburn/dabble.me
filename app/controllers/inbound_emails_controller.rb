class InboundEmailsController < Griddler::EmailsController
  MAX_SIGNATURE_AGE = 9.hours

  before_action :authenticate_mailgun_request!, only: [:create]

  private

  def authenticate_mailgun_request!
    return true if legit_request?

    Sentry.capture_message(
      'Mailgun inbound signature did not match.',
      level: :info,
      extra: { timestamp: timestamp, token: token }
    )
    head(:forbidden)
    false
  end

  def legit_request?
    signing_key = ENV['MAILGUN_SIGNING_KEY']
    return false if signing_key.blank? || token.blank? || actual_signature.blank? || !fresh_timestamp?

    expected = OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, signing_key, "#{timestamp}#{token}")
    ActiveSupport::SecurityUtils.secure_compare(actual_signature, expected)
  end

  def fresh_timestamp?
    timestamp.match?(/\A\d+\z/) && (Time.now.to_i - timestamp.to_i).abs <= MAX_SIGNATURE_AGE
  end

  def signature_hash
    raw = params[:signature]
    raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash) ? raw : {}
  end

  def timestamp
    (params[:timestamp].presence || signature_hash[:timestamp]).to_s
  end

  def token
    (params[:token].presence || signature_hash[:token]).to_s
  end

  def actual_signature
    raw = params[:signature]
    (raw.is_a?(String) ? raw : signature_hash[:signature]).to_s
  end
end
