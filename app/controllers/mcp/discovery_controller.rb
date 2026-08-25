# frozen_string_literal: true

module Mcp
  class DiscoveryController < ApplicationController
    skip_forgery_protection

    before_action :set_discovery_cors_headers

    # GET /.well-known/webmcp
    def webmcp
      render_public_json(webmcp_catalog.webmcp_manifest, content_type: 'application/json')
    end

    # GET /mcp/server-card and GET /.well-known/mcp.json
    def server_card
      render_public_json(webmcp_catalog.server_card, content_type: 'application/mcp-server-card+json')
    end

    # GET /.well-known/ai-catalog.json
    def ai_catalog
      render_public_json(webmcp_catalog.ai_catalog, content_type: 'application/ai-catalog+json')
    end

    # GET /.well-known/api-catalog
    def api_catalog
      render_public_json(webmcp_catalog.api_catalog, content_type: 'application/linkset+json')
    end

    # GET /.well-known/agents.md
    def agents
      body = webmcp_catalog.agents_md
      return unless stale?(etag: Digest::SHA256.hexdigest(body), public: true)

      expires_in 1.hour, public: true
      render plain: body, content_type: 'text/markdown; charset=utf-8'
    end

    # GET/POST /webmcp/tools/:name
    def invoke_tool
      if request.options?
        head :no_content
        return
      end

      payload = webmcp_catalog.invoke_public_tool(params[:name])
      if payload.blank?
        render json: {
          'content' => [{ 'type' => 'text', 'text' => 'Unknown WebMCP reference tool.' }],
          'isError' => true
        }, status: :not_found
        return
      end

      render json: payload
    end

    private

    def render_public_json(payload, content_type:)
      json = payload.to_json
      return unless stale?(etag: Digest::SHA256.hexdigest(json), public: true)

      expires_in 1.hour, public: true
      render json: payload, content_type: content_type
    end

    def set_discovery_cors_headers
      response.set_header('Access-Control-Allow-Origin', '*')
      response.set_header('Access-Control-Allow-Methods', 'GET, POST, HEAD, OPTIONS')
      response.set_header('Access-Control-Allow-Headers', 'Content-Type, If-None-Match, Accept')
      response.set_header('Access-Control-Expose-Headers', 'ETag')
    end
  end
end
