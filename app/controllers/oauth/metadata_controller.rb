# frozen_string_literal: true

module Oauth
  class MetadataController < ApplicationController
    skip_forgery_protection

    # GET /.well-known/oauth-authorization-server
    def authorization_server
      render json: {
        issuer: request.base_url,
        authorization_endpoint: oauth_authorization_url(**metadata_url_options),
        token_endpoint: oauth_token_url(**metadata_url_options),
        registration_endpoint: oauth_registrations_url(**metadata_url_options),
        revocation_endpoint: oauth_revoke_url(**metadata_url_options),
        introspection_endpoint: oauth_introspect_url(**metadata_url_options),
        response_types_supported: ['code'],
        grant_types_supported: %w[authorization_code refresh_token],
        token_endpoint_auth_methods_supported: ['none'],
        scopes_supported: ['mcp:access'],
        code_challenge_methods_supported: ['S256']
      }
    end

    # GET /.well-known/oauth-protected-resource
    def protected_resource
      render json: {
        resource: "#{request.base_url}/mcp",
        resource_name: 'Dabble Me MCP',
        authorization_servers: [request.base_url],
        bearer_methods_supported: ['header'],
        scopes_supported: ['mcp:access']
      }
    end

    private

    def metadata_url_options
      { host: request.host, protocol: request.scheme, port: request.port }
    end
  end
end
