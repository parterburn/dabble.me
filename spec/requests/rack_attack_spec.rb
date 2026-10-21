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
    env_config['action_dispatch.show_exceptions'] = true
    yield
  ensure
    env_config['action_dispatch.show_exceptions'] = previous
  end
end
