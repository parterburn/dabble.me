class EmailEventsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:process]
  before_action      :authenticate_mailgun_request!, only: [:process]

  def process
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
    if @user.is_free?
      @user.frequency = []
      @user.save
    end
    ActionMailer::Base.mail(
                            from: "hello@#{ENV['MAIN_DOMAIN']}",
                            to: "hello@#{ENV['MAIN_DOMAIN']}",
                            subject: "[DABBLE.ME] #{event_type}",
                            body: "#{recipient} (#{@user.plan})\n\n-----------\n\n#{delivery_status}"
                            ).deliver
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
