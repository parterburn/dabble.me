# Encrypted X OAuth 2.0 tokens on User + auto-refresh.
# Columns: x_access_token, x_refresh_token, x_uid, x_username (all plaintext in DB, encrypted here).
module User::XOauth
  extend ActiveSupport::Concern

  TOKEN_URL = 'https://api.x.com/2/oauth2/token'

  def x_connected?
    x_refresh_token.present?
  end

  def disconnect_x!
    update!(x_access_token: nil, x_refresh_token: nil, x_uid: nil, x_username: nil)
  end

  # Returns a fresh access token, refreshing if needed.
  def fresh_x_access_token!
    return nil unless x_connected?

    refresh_x_tokens!
    x_access_token
  end

  # Exchanges a one-time auth code for tokens and saves them.
  def save_x_tokens_from_code!(code:, redirect_uri:, code_verifier:)
    tokens = exchange_x_code(code: code, redirect_uri: redirect_uri, code_verifier: code_verifier)
    update!(x_access_token: tokens['access_token'], x_refresh_token: tokens['refresh_token'])

    # Fetch profile to store uid/username
    client = XApiClient.new(access_token: tokens['access_token'])
    if (profile = client.current_user)
      update!(x_uid: profile.dig('data', 'id'), x_username: profile.dig('data', 'username'))
    end
  end

  private

  def refresh_x_tokens!
    conn = Faraday.new(TOKEN_URL) do |f|
      f.request :url_encoded
      f.response :json
    end

    basic = Base64.strict_encode64("#{ENV['X_CLIENT_ID']}:#{ENV['X_CLIENT_SECRET']}")
    resp = conn.post('', { grant_type: 'refresh_token', refresh_token: x_refresh_token }) do |req|
      req.headers['Authorization'] = "Basic #{basic}"
    end

    if resp.success?
      update!(x_access_token: resp.body['access_token'], x_refresh_token: resp.body['refresh_token'])
    else
      Sentry.capture_message("X token refresh failed", level: :warning, extra: { user_id: id, status: resp.status, body: resp.body })
      nil
    end
  end

  def exchange_x_code(code:, redirect_uri:, code_verifier:)
    conn = Faraday.new(TOKEN_URL) do |f|
      f.request :url_encoded
      f.response :json
    end

    basic = Base64.strict_encode64("#{ENV['X_CLIENT_ID']}:#{ENV['X_CLIENT_SECRET']}")
    body = { grant_type: 'authorization_code', code: code, redirect_uri: redirect_uri, code_verifier: code_verifier }
    resp = conn.post('', body) { |req| req.headers['Authorization'] = "Basic #{basic}" }

    raise "X token exchange failed: #{resp.status} — #{resp.body}" unless resp.success?
    resp.body
  end
end
