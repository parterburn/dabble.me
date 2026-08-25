# frozen_string_literal: true

module Mcp
  # Session-scoped journal actions for in-page WebMCP tools.
  # Uses the signed-in browser user only — never a user id from tool arguments.
  class WebmcpJournal
    class Error < StandardError
      attr_reader :status

      def initialize(message, status: :unprocessable_entity)
        super(message)
        @status = status
      end
    end

    def initialize(user:)
      @user = user
    end

    def session_data
      {
        signed_in: true,
        first_name: user.first_name,
        is_pro: user.is_pro?,
        can_search: user.is_pro?,
        can_write: user.is_pro?,
        today: today.iso8601,
        write_path: '/entries/new',
        search_path: '/search',
        day_path_pattern: '/entries/YYYY/M/D',
        note: session_note
      }
    end

    def search(query:, start_date: nil, end_date: nil, limit: nil)
      require_pro!(:search)
      raise Error, 'query is required' if query.to_s.strip.blank?

      result = searcher.search(
        query: query,
        limit: limit || 20,
        since: start_date,
        until_date: end_date
      )
      serialize_list(result, query: query)
    end

    def list(start_date: nil, end_date: nil, limit: nil)
      result = searcher.list(
        limit: limit || 20,
        since: start_date,
        until_date: end_date
      )
      serialize_list(result)
    end

    def analyze(start_date: nil, end_date: nil)
      require_pro!(:analyze)
      result = searcher.analyze(since: start_date, until_date: end_date)
      {
        total_entries: result[:total_matches],
        date_range: result[:date_range],
        entry_count_by_year: result[:entry_count_by_year],
        top_hashtags: result[:most_used_hashtags].map { |tag| { hashtag: tag[:tag], count: tag[:count] } },
        average_words_per_entry: result[:average_entry_length_words],
        sample_entries: result[:sample_highlights].map { |row| row.merge(url: day_path(row[:date])) }
      }
    end

    private

    attr_reader :user

    def searcher
      @searcher ||= EntrySearch.new(user: user)
    end

    def require_pro!(action)
      return if user.is_pro? && !user.deletion_pending?

      raise Error.new(
        "Dabble Me PRO is required to #{action} the journal on the web. The user can upgrade at /subscribe.",
        status: :forbidden
      )
    end

    def serialize_list(result, query: nil)
      {
        query: query,
        total_matches: result[:total_matches],
        entries: result[:entries].map do |entry|
          Tools::Helpers.normalize_entry_row(entry).merge(url: day_path(entry[:date]))
        end
      }.compact
    end

    def day_path(date)
      parsed = date.respond_to?(:to_date) ? date.to_date : Date.iso8601(date.to_s)
      "/entries/#{parsed.year}/#{parsed.month}/#{parsed.day}"
    end

    def today
      tz = ActiveSupport::TimeZone[user.send_timezone.presence || 'UTC'] || Time.zone
      Time.current.in_time_zone(tz).to_date
    end

    def session_note
      if user.deletion_pending?
        'This account is pending deletion. Journal tools are disabled.'
      elsif user.is_pro?
        'Search, list, and analyze run against this browser session. Draft a new entry on the write page and leave Create Entry for the user.'
      else
        'This signed-in account can open existing entries. Search, analysis, and web drafts require Dabble Me PRO.'
      end
    end
  end
end
