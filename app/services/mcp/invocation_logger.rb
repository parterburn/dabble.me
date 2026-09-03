# frozen_string_literal: true

module Mcp
  # Append-only usage log for MCP tool calls. Never stores query text or entry bodies.
  class InvocationLogger
    class << self
      def record(user_id:, tool_name:, source:, success:, result_count: nil, duration_ms: nil, oauth_application_id: nil)
        return if user_id.blank? || tool_name.blank?

        McpToolInvocation.create!(
          user_id: user_id,
          tool_name: tool_name.to_s,
          source: source.to_s,
          success: success,
          result_count: result_count,
          duration_ms: duration_ms,
          oauth_application_id: oauth_application_id,
          created_at: Time.current
        )
      rescue StandardError => e
        Sentry.capture_exception(e, extra: { mcp_tool_name: tool_name, mcp_source: source })
        nil
      end

      def record_from_response(tool_name:, server_context:, source:, response:, duration_ms:)
        record(
          user_id: server_context && server_context[:user_id],
          tool_name: tool_name,
          source: source,
          success: response.respond_to?(:error?) ? !response.error? : true,
          result_count: result_count_from(response),
          duration_ms: duration_ms,
          oauth_application_id: server_context && server_context[:oauth_application_id]
        )
      end

      def result_count_from(payload)
        data = if payload.respond_to?(:structured_content)
          payload.structured_content
        else
          payload
        end
        return nil unless data.is_a?(Hash)

        hash = data.with_indifferent_access
        return hash[:total_matches] if hash.key?(:total_matches)
        return hash[:total_entries] if hash.key?(:total_entries)
        return 1 if hash[:success]
        return hash[:entries].size if hash[:entries].is_a?(Array)

        nil
      end
    end
  end
end
