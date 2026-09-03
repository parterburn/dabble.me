# frozen_string_literal: true

module Webmcp
  class JournalController < ApplicationController
    before_action :require_signed_in_json
    before_action :reject_pending_deletion

    def session_info
      invoke_journal { journal.session_data }
    end

    def search
      invoke_journal('search_entries') do
        journal.search(
          query: tool_arguments[:query],
          start_date: tool_arguments[:start_date],
          end_date: tool_arguments[:end_date],
          limit: tool_arguments[:limit]
        )
      end
    end

    def list
      invoke_journal('list_entries') do
        journal.list(
          start_date: tool_arguments[:start_date],
          end_date: tool_arguments[:end_date],
          limit: tool_arguments[:limit]
        )
      end
    end

    def analyze
      invoke_journal('analyze_entries') do
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

    def invoke_journal(tool_name = nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      data = yield
      log_journal_invocation(tool_name, success: true, payload: data, started: started) if tool_name
      render json: {
        'content' => [{ 'type' => 'text', 'text' => JSON.pretty_generate(data) }],
        'isError' => false,
        'data' => data
      }
    rescue Mcp::WebmcpJournal::Error => e
      log_journal_invocation(tool_name, success: false, started: started) if tool_name
      render_tool_error(e.message, e.status)
    rescue ArgumentError => e
      log_journal_invocation(tool_name, success: false, started: started) if tool_name
      render_tool_error(e.message, :unprocessable_entity)
    end

    def log_journal_invocation(tool_name, success:, started:, payload: nil)
      Mcp::InvocationLogger.record(
        user_id: current_user&.id,
        tool_name: tool_name,
        source: 'webmcp',
        success: success,
        result_count: Mcp::InvocationLogger.result_count_from(payload),
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      )
    end

    def render_tool_error(message, status)
      render json: {
        'content' => [{ 'type' => 'text', 'text' => message }],
        'isError' => true
      }, status: status
    end
  end
end
