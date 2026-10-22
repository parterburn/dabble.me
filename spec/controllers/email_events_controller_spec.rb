require 'rails_helper'

RSpec.describe EmailEventsController, type: :controller do
  let(:signing_key) { 'test-signing-key' }
  let(:user) { FactoryBot.create(:user, plan: 'Free', frequency: ['Sun']) }
  let(:timestamp) { Time.now.to_i.to_s }
  let(:token) { SecureRandom.hex(25) }
  let(:signature) { OpenSSL::HMAC.hexdigest('SHA256', signing_key, "#{timestamp}#{token}") }

  around do |example|
    original = ENV['MAILGUN_SIGNING_KEY']
    ENV['MAILGUN_SIGNING_KEY'] = signing_key
    example.run
  ensure
    ENV['MAILGUN_SIGNING_KEY'] = original
  end

  def post_event(sig: signature, ts: timestamp, tok: token)
    post :create, params: {
      signature: { signature: sig, timestamp: ts, token: tok },
      'event-data': { event: 'failed', recipient: user.email }
    }
  end

  it 'processes a correctly signed bounce' do
    expect { post_event }.to change { user.reload.emails_bounced }.by(1)
    expect(response).to have_http_status(:ok)
  end

  it 'rejects a bad signature with 403' do
    expect { post_event(sig: 'nope') }.not_to(change { user.reload.emails_bounced })
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects a missing signature block with 403 instead of erroring' do
    post :create, params: { 'event-data': { event: 'failed', recipient: user.email } }
    expect(response).to have_http_status(:forbidden)
  end

  it 'accepts a retry signed within the retry window' do
    late = 8.hours.ago.to_i.to_s
    post_event(ts: late, sig: OpenSSL::HMAC.hexdigest('SHA256', signing_key, "#{late}#{token}"))
    expect(response).to have_http_status(:ok)
  end

  it 'rejects a timestamp older than the retry window' do
    old = 10.hours.ago.to_i.to_s
    post_event(ts: old, sig: OpenSSL::HMAC.hexdigest('SHA256', signing_key, "#{old}#{token}"))
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects everything when no signing key is configured' do
    ENV['MAILGUN_SIGNING_KEY'] = nil
    post_event
    expect(response).to have_http_status(:forbidden)
  end
end

RSpec.describe InboundEmailsController, type: :controller do
  let(:signing_key) { 'test-inbound-signing-key' }
  let(:user) { FactoryBot.create(:user, plan: 'Free', frequency: ['Sun']) }
  let(:timestamp) { Time.now.to_i.to_s }
  let(:token) { SecureRandom.hex(25) }
  let(:signature) { OpenSSL::HMAC.hexdigest('SHA256', signing_key, "#{timestamp}#{token}") }

  around do |example|
    original = ENV['MAILGUN_SIGNING_KEY']
    ENV['MAILGUN_SIGNING_KEY'] = signing_key
    example.run
  ensure
    ENV['MAILGUN_SIGNING_KEY'] = original
  end

  it 'rejects unsigned POSTs to /email_processor with 403' do
    expect(EmailProcessor).not_to receive(:new)

    post :create, params: {
      From: user.email,
      To: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}",
      recipient: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}",
      subject: 'Hello',
      'body-plain': 'Unsigned attempt'
    }

    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects expired Mailgun signatures on /email_processor with 403' do
    old_ts = 10.hours.ago.to_i.to_s
    old_sig = OpenSSL::HMAC.hexdigest('SHA256', signing_key, "#{old_ts}#{token}")

    post :create, params: {
      timestamp: old_ts,
      token: token,
      signature: old_sig,
      From: user.email,
      To: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}"
    }

    expect(response).to have_http_status(:forbidden)
  end

  it 'accepts a validly signed Mailgun inbound request' do
    processor = instance_double(EmailProcessor, process: true)
    allow(EmailProcessor).to receive(:new).and_return(processor)

    post :create, params: {
      timestamp: timestamp,
      token: token,
      signature: signature,
      From: "#{user.full_name} <#{user.email}>",
      sender: user.email,
      To: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}",
      recipient: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}",
      subject: 'Signed entry',
      'body-plain': 'Signed body'
    }

    expect(response).to have_http_status(:ok)
    expect(processor).to have_received(:process)
  end
end
