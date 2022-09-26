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
    @user.frequency = [] if @user.is_free?
    @user.save
  end

  # ========================================
  # AUTHENTICATION
  # ========================================

  def mailgun_auth_params
    params.permit(signature: [:signature, :timestamp, :token])
  end

  def event_params
    mailgun_auth_params[:signature].to_hash
  end

  def timestamp
    event_params.fetch('timestamp')
  end

  def token
    event_params.fetch('token')
  end

  def actual_signature
    event_params.fetch('signature')
  end

  def legit_request?
    digest = OpenSSL::Digest::SHA256.new
    data = [timestamp, token].join
    actual_signature == OpenSSL::HMAC.hexdigest(digest, ENV['MAILGUN_API_KEY'], data)
  end

  def authenticate_mailgun_request!
    if legit_request?
      true
    else
      head(:forbidden, text: 'Mailgun signature did not match.')
      false
    end
  end
end
