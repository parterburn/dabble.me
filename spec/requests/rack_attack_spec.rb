# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rack::Attack', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # Rack::Attack counts in fixed windows keyed by Time.now (20 seconds for
  # sign-ins, 5 minutes for the probe ban). Freeze time so an example can't
  # straddle a window boundary and start counting from zero partway through.
  around do |example|
    original = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    freeze_time { example.run }
  ensure
    Rack::Attack.cache.store = original
  end

  it 'throttles sign-in attempts against the same email across IP addresses' do
    email = 'throttle-target@example.com'

    statuses = Array.new(6) do |index|
      post '/users/sign_in',
        params: { user: { email: email, password: 'wrong-password' } },
        env: { 'REMOTE_ADDR' => "203.0.113.#{index + 1}" }
      response.status
    end

    expect(statuses.first(5)).to all(be < 429)
    expect(statuses.last).to eq(429)
  end

  it 'throttles password reset posts' do
    statuses = Array.new(6) do
      post '/users/password',
        params: { user: { email: 'nobody@example.com' } },
        env: { 'REMOTE_ADDR' => '203.0.113.20' }
      response.status
    end

    expect(statuses.first(5)).to all(be < 429)
    expect(statuses.last).to eq(429)
  end

  ['/users/sign_in.json', '/users/sign_in/', '/users/sign_in.html'].each do |path|
    it "throttles sign-in attempts posted to #{path}" do
      statuses = Array.new(6) do |index|
        post path,
          params: { user: { email: "variant-#{index}@example.com", password: 'wrong-password' } },
          env: { 'REMOTE_ADDR' => '203.0.113.70' }
        response.status
      end

      expect(statuses.first(5)).to all(be < 429)
      expect(statuses.last).to eq(429)
    end
  end

  it 'counts sign-in attempts sent as a JSON body against the email' do
    email = 'json-target@example.com'

    statuses = Array.new(6) do |index|
      post '/users/sign_in',
        params: { user: { email: email, password: 'wrong-password' } }.to_json,
        headers: { 'CONTENT_TYPE' => 'application/json' },
        env: { 'REMOTE_ADDR' => "203.0.113.#{index + 80}" }
      response.status
    end

    expect(statuses.first(5)).to all(be < 429)
    expect(statuses.last).to eq(429)
  end

  it 'throttles OTP guesses posted to a format variant of the path' do
    statuses = Array.new(11) do |index|
      put '/users/otp/credentials.json',
        params: { user: { challenge: "c#{index}", token: '000000' } },
        env: { 'REMOTE_ADDR' => '203.0.113.90' }
      response.status
    end

    expect(statuses.first(10)).to all(be < 429)
    expect(statuses.last).to eq(429)
  end

  it 'reads no email from a malformed JSON body instead of raising' do
    env = Rack::MockRequest.env_for('/users/sign_in', method: 'POST', input: '{not json',
                                                      'CONTENT_TYPE' => 'application/json')

    expect(Rack::Attack.submitted_email(Rack::Attack::Request.new(env))).to be_nil
  end

  it 'throttles signup posts from one IP' do
    statuses = Array.new(6) do |index|
      post '/users',
        params: {
          user: {
            email: "signup-#{index}@example.com",
            password: 'password1',
            password_confirmation: 'password1'
          }
        },
        env: { 'REMOTE_ADDR' => '203.0.113.30' }
      response.status
    end

    expect(statuses.first(5)).to all(be < 429)
    expect(statuses.last).to eq(429)
  end

  it 'throttles passkey sign-in posts from one IP' do
    statuses = Array.new(11) do
      post '/passkeys/sessions', params: {}, as: :json, env: { 'REMOTE_ADDR' => '203.0.113.40' }
      response.status
    end

    expect(statuses.first(10)).to all(be < 429)
    expect(statuses.last).to eq(429)
  end

  it 'throttles OTP challenge guesses per challenge across rotating IPs' do
    challenge = SecureRandom.hex(16)

    statuses = Array.new(6) do |index|
      put '/users/otp/credentials',
        params: { user: { challenge: challenge, token: '000000' } },
        env: { 'REMOTE_ADDR' => "198.51.100.#{index + 1}" }
      response.status
    end

    expect(statuses.first(5)).to all(be < 429)
    expect(statuses.last).to eq(429)
  end

  it 'bans an IP after repeated missing paths' do
    with_production_exceptions do
      Rack::Attack::PROBE_BAN_MAXRETRY.times do |index|
        get "/zzz-missing-#{index}", env: { 'REMOTE_ADDR' => '203.0.113.40' }
        expect(response).to have_http_status(:not_found)
      end

      get '/zzz-missing-final', env: { 'REMOTE_ADDR' => '203.0.113.40' }
      expect(response).to have_http_status(:forbidden)

      get '/', env: { 'REMOTE_ADDR' => '203.0.113.41' }
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  it 'bans using CF-Connecting-IP when REMOTE_ADDR is a shared proxy hop' do
    with_production_exceptions do
      proxy = '10.0.0.5'
      client = '203.0.113.60'

      Rack::Attack::PROBE_BAN_MAXRETRY.times do |index|
        get "/zzz-cf-missing-#{index}",
          env: {
            'REMOTE_ADDR' => proxy,
            'HTTP_CF_CONNECTING_IP' => client
          }
        expect(response).to have_http_status(:not_found)
      end

      get '/zzz-cf-missing-final',
        env: {
          'REMOTE_ADDR' => proxy,
          'HTTP_CF_CONNECTING_IP' => client
        }
      expect(response).to have_http_status(:forbidden)

      # Same proxy hop, different real client — must stay unblocked.
      get '/',
        env: {
          'REMOTE_ADDR' => proxy,
          'HTTP_CF_CONNECTING_IP' => '203.0.113.61'
        }
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  it 'does not ban when only a private REMOTE_ADDR is visible' do
    with_production_exceptions do
      (Rack::Attack::PROBE_BAN_MAXRETRY + 1).times do |index|
        get "/zzz-private-missing-#{index}", env: { 'REMOTE_ADDR' => '10.0.0.8' }
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end

  it 'does not count asset misses toward the probe ban' do
    with_production_exceptions do
      Rack::Attack::PROBE_BAN_MAXRETRY.times do |index|
        get "/assets/missing-#{index}.css", env: { 'REMOTE_ADDR' => '203.0.113.50' }
      end

      get '/', env: { 'REMOTE_ADDR' => '203.0.113.50' }
      expect(response).not_to have_http_status(:forbidden)
    end
  end

  def with_production_exceptions
    env_config = Rails.application.env_config
    previous = env_config['action_dispatch.show_exceptions']
    env_config['action_dispatch.show_exceptions'] = :all
    yield
  ensure
    env_config['action_dispatch.show_exceptions'] = previous
  end
end
