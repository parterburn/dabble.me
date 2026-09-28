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
