# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rack::Attack', type: :request do
  around do |example|
    original = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
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
