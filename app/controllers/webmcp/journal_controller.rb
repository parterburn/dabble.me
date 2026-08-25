# frozen_string_literal: true

module Webmcp
  class JournalController < ApplicationController
    before_action :require_signed_in_json
    before_action :reject_pending_deletion

    def session_info
      invoke_journal { journal.session_data }
    end

    def search
      invoke_journal do
        journal.search(
          query: tool_arguments[:query],
          start_date: tool_arguments[:start_date],
          end_date: tool_arguments[:end_date],
          limit: tool_arguments[:limit]
        )
      end
    end

    def list
      invoke_journal do
        journal.list(
          start_date: tool_arguments[:start_date],
          end_date: tool_arguments[:end_date],
          limit: tool_arguments[:limit]
        )
      end
    end

    def analyze
      invoke_journal do
        journal.analyze(
          start_date: tool_arguments[:start_date],
          end_date: tool_arguments[:end_date]
        )
      end
    end

    private

    def journal
      @journal ||= Mcp::WebmcpJournal.new(user: current_user)
    end

    def tool_arguments
      raw = if request.media_type.to_s.include?('json') && request.raw_post.present?
        JSON.parse(request.raw_post)
      else
        params.to_unsafe_h
      end
      raw = {} unless raw.is_a?(Hash)
      raw.deep_symbolize_keys.slice(:query, :start_date, :end_date, :limit)
    rescue JSON::ParserError
      {}
    end

    def require_signed_in_json
      return if user_signed_in?

      render_tool_error('Sign in to Dabble Me in this browser first, then call the journal tools again.', :unauthorized)
    end

    def reject_pending_deletion
      return unless current_user&.deletion_pending?

      render_tool_error('This Dabble Me account is pending deletion.', :forbidden)
    end

    def invoke_journal
      data = yield
      render json: {
        'content' => [{ 'type' => 'text', 'text' => JSON.pretty_generate(data) }],
        'isError' => false,
        'data' => data
      }
    rescue Mcp::WebmcpJournal::Error => e
      render_tool_error(e.message, e.status)
    rescue ArgumentError => e
      render_tool_error(e.message, :unprocessable_entity)
    end

    def render_tool_error(message, status)
      render json: {
        'content' => [{ 'type' => 'text', 'text' => message }],
        'isError' => true
      }, status: status
    end
  end
end
