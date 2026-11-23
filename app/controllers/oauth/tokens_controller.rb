# frozen_string_literal: true

module Oauth
  class TokensController < Doorkeeper::TokensController
    before_action :refuse_unknown_resource, only: :create
    before_action :refuse_mobile_app_code_exchange, only: :create
    before_action :check_refresh_token_reuse, only: :create
    before_action :refuse_idle_refresh_token, only: :create

    private

    # A refresh token unused past its app's idle limit (OauthIdleExpiry) is revoked and
    # refused, so the app has to connect again.
    def refuse_idle_refresh_token
      return unless params[:grant_type] == 'refresh_token' && params[:refresh_token].present?

      token = Doorkeeper.config.access_token_model.by_refresh_token(params[:refresh_token].to_s)
      return unless token && !token.revoked? && OauthIdleExpiry.idle?(token)

      token.revoke
      render_token_error(:invalid_grant)
    end

    # RFC 8707 §2: a token request may name the resource too (a refresh can narrow it). We serve
    # one resource, so anything else gets invalid_target instead of a token it can't be used for.
    def refuse_unknown_resource
      return if Mcp::OauthRules.allowed_resource?(params[:resource], request.base_url)

      render_token_error(:invalid_target)
    end

    # The iOS app no longer signs in on the web (Oauth::AuthorizationsController refuses its
    # client), so no code of its can be exchanged here. Its refresh tokens still renew.
    def refuse_mobile_app_code_exchange
      return unless params[:grant_type] == 'authorization_code' && params[:client_id].to_s == MobileApp::CLIENT_ID

      render_token_error(:unauthorized_client)
    end

    # A rotated refresh token sent again (OauthRefreshReuse). Doorkeeper refuses it either way;
    # this also cuts off whoever refreshed with it first.
    def check_refresh_token_reuse
      return unless params[:grant_type] == 'refresh_token' && params[:refresh_token].present?

      token = Doorkeeper.config.access_token_model.by_refresh_token(params[:refresh_token].to_s)
      return unless token&.revoked?

      OauthRefreshReuse.handle!(token)
      render_token_error(:invalid_grant)
    end

    def render_token_error(name)
      error = Doorkeeper::OAuth::ErrorResponse.new(name: name)
      headers['Cache-Control'] = 'no-store'
      render json: error.body, status: :bad_request
    end
  end
end
