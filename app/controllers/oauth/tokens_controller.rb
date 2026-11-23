# frozen_string_literal: true

module Oauth
  class TokensController < Doorkeeper::TokensController
    before_action :refuse_unknown_resource, only: :create
    before_action :refuse_idle_refresh_token, only: :create

    private

    # A refresh token unused past its app's idle limit (OauthIdleExpiry) is revoked and
    # refused, so the app has to connect again.
    def refuse_idle_refresh_token
      return unless params[:grant_type] == 'refresh_token' && params[:refresh_token].present?

      token = Doorkeeper.config.access_token_model.by_refresh_token(params[:refresh_token].to_s)
      return unless token && !token.revoked? && OauthIdleExpiry.idle?(token)

      token.revoke
      error = Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_grant)
      headers['Cache-Control'] = 'no-store'
      render json: error.body, status: :bad_request
    end

    # RFC 8707 §2: a token request may name the resource too (a refresh can narrow it). We serve
    # one resource, so anything else gets invalid_target instead of a token it can't be used for.
    def refuse_unknown_resource
      return if Mcp::OauthRules.allowed_resource?(params[:resource], request.base_url)

      error = Doorkeeper::OAuth::ErrorResponse.new(name: :invalid_target)
      headers['Cache-Control'] = 'no-store'
      render json: error.body, status: :bad_request
    end
  end
end
