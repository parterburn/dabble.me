# frozen_string_literal: true

class McpController < ApplicationController
  include Doorkeeper::Rails::Helpers

  skip_forgery_protection

  before_action :ensure_mcp_post_only
  before_action -> { doorkeeper_authorize! 'mcp:access' }

  # Streamable HTTP MCP endpoint (request/response JSON only; no SSE).
  def invoke
    user = User.find(doorkeeper_token.resource_owner_id)
    Sentry.set_user(id: user.id)
    Sentry.set_tags(mcp: true, mcp_oauth: true)

    payload = request.raw_post
    payload = request.body.read if payload.blank?

    response_json = Mcp::DabbleServer.build_for_user(user).handle_json(payload)

    if response_json.present?
      render json: response_json, content_type: 'application/json'
    else
      head :accepted
    end
  end

  private

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
