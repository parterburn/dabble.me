# frozen_string_literal: true

module Oauth
  class TokensController < Doorkeeper::TokensController
    before_action :refuse_unknown_resource, only: :create

    private

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
