# frozen_string_literal: true

class McpController < ApplicationController
  include Doorkeeper::Rails::Helpers

  skip_forgery_protection

  # JSON-RPC methods answered without a token, so directories, scanners and clients can read the
  # server's name, tools and prompts before sign-in. None of them reads or writes journal data.
  # Everything else (tools/call above all) still gets a 401 whose WWW-Authenticate header points at
  # the protected resource metadata, which is what makes Claude and ChatGPT start OAuth.
  PUBLIC_METHODS = %w[
    initialize
    notifications/initialized
    notifications/cancelled
    ping
    tools/list
    prompts/list
    prompts/get
  ].freeze

  # The tokenless path answers one small JSON-RPC message at a time. A batch (dropped from MCP in
  # 2025-06-18) or a large body would let anyone make the server build a response many times its
  # size, so either one goes through the normal token check and gets the 401.
  PUBLIC_MAX_BODY_BYTES = 16.kilobytes

  before_action :ensure_mcp_post_only
  before_action :refuse_cross_origin_request
  before_action -> { doorkeeper_authorize! 'mcp:access' }, unless: :public_discovery_request?

  # Streamable HTTP MCP endpoint (request/response JSON only; no SSE).
  def invoke
    return invoke_public if public_discovery_request?

    user = User.find(doorkeeper_token.resource_owner_id)
    Sentry.set_user(id: user.id)
    Sentry.set_tags(mcp: true, mcp_oauth: true)

    response_json = Mcp::DabbleServer.build_for_user(
      user,
      oauth_application_id: doorkeeper_token.application_id
    ).handle_json(mcp_payload)

    if response_json.present?
      render json: response_json, content_type: 'application/json'
    else
      head :accepted
    end
  end

  private

  def invoke_public
    Sentry.set_tags(mcp: true, mcp_oauth: false)
    response_json = Mcp::DabbleServer.build_public.handle_json(mcp_payload)
    if response_json.present?
      render json: response_json, content_type: 'application/json'
    else
      head :accepted
    end
  end

  def mcp_payload
    @mcp_payload ||= request.raw_post.presence || request.body.read
  end

  # Only a request that carries no token at all. A stale or revoked token always gets the 401, so
  # a client holding one refreshes it or signs in again instead of quietly losing access.
  def public_discovery_request?
    return @public_discovery_request if defined?(@public_discovery_request)

    @public_discovery_request = request.post? && !bearer_token_sent? && public_methods_only?
  end

  def bearer_token_sent?
    Doorkeeper::OAuth::Token.from_request(request, *Doorkeeper.config.access_token_methods).present?
  end

  def public_methods_only?
    return false if mcp_payload.blank? || mcp_payload.bytesize > PUBLIC_MAX_BODY_BYTES

    message = JSON.parse(mcp_payload)
    message.is_a?(Hash) && PUBLIC_METHODS.include?(message['method'])
  rescue JSON::ParserError
    false
  end

  # MCP Streamable HTTP: servers MUST validate Origin (DNS rebinding). Claude, ChatGPT and other
  # MCP clients call from their servers and send no Origin; a browser always does, and a page on
  # another site has no business calling /mcp. The endpoint sends no CORS headers either, so a
  # foreign page couldn't read the answer anyway; this stops the request before it runs.
  def refuse_cross_origin_request
    origin = request.headers['Origin']
    return if origin.blank? || origin == request.base_url

    render json: {
      jsonrpc: '2.0',
      id: nil,
      error: { code: -32_003, message: 'Forbidden: cross-origin requests to /mcp are not allowed' }
    }, status: :forbidden
  end

  # RFC 6750 §3.1: a request that sent no token gets a bare challenge with no error code, so
  # clients read it as "sign in" rather than "your token is bad".
  def www_authenticate_challenge(error)
    challenge = if bearer_token_sent?
      error.headers['WWW-Authenticate'].presence || 'Bearer'
    else
      %(Bearer realm="#{Doorkeeper.config.realm}")
    end
    "#{challenge}, resource_metadata=\"#{request.base_url}/.well-known/oauth-protected-resource/mcp\", " \
      'scope="mcp:access"'
  end

  def doorkeeper_render_error_with(error)
    response.set_header('WWW-Authenticate', www_authenticate_challenge(error))
    super
  end

  def ensure_mcp_post_only
    return if request.post?

    response.set_header('Allow', 'POST')
    head :method_not_allowed
  end

  def doorkeeper_unauthorized_render_options(error:)
    {
      json: {
        jsonrpc: '2.0',
        id: nil,
        error: { code: -32_001, message: 'Unauthorized' }
      },
      status: :unauthorized
    }
  end

  def doorkeeper_forbidden_render_options(error:)
    {
      json: {
        jsonrpc: '2.0',
        id: nil,
        error: { code: -32_003, message: 'Forbidden' }
      },
      status: :forbidden
    }
  end
end
