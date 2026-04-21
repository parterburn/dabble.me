class McpController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate_mcp_user!

  def create
    case params[:method]
    when 'initialize'
      render json: initialize_response
    when 'tools/list'
      render json: tools_list_response
    when 'tools/call'
      render json: tools_call_response
    else
      render_mcp_error(code: -32601, message: 'Method not found')
    end
  rescue ActionController::ParameterMissing => e
    render_mcp_error(code: -32602, message: e.message)
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { mcp_user_id: @mcp_user&.id, method: params[:method] })
    render_mcp_error(code: -32603, message: 'Internal server error')
  end

  private

  def authenticate_mcp_user!
    token = mcp_access_token
    @mcp_user = User.authenticate_mcp_token(token)

    unless @mcp_user
      response.set_header('WWW-Authenticate', 'Bearer realm="Dabble Me MCP"')
      render json: { jsonrpc: '2.0', id: params[:id], error: { code: -32001, message: 'Unauthorized' } }, status: :unauthorized
      return
    end

    @mcp_user.mark_mcp_token_used!
    Sentry.set_user(id: @mcp_user.id)
    Sentry.set_tags(mcp: true)
  end

  def mcp_access_token
    bearer_token || params[:access_token].presence&.strip
  end

  def bearer_token
    authenticate_with_http_token do |token, _options|
      return token.to_s.strip
    end

    nil
  end

  def initialize_response
    {
      jsonrpc: '2.0',
      id: params[:id],
      result: {
        protocolVersion: '2025-03-26',
        serverInfo: {
          name: 'dabble-me',
          version: '1.0.0'
        },
        capabilities: {
          tools: {}
        }
      }
    }
  end

  def tools_list_response
    {
      jsonrpc: '2.0',
      id: params[:id],
      result: {
        tools: [
          {
            name: 'search_entries',
            description: 'Search your own Dabble Me entries by keyword or quoted phrase, optionally constrained by date range.',
            inputSchema: {
              type: 'object',
              properties: {
                query: { type: 'string' },
                start_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive start date.' },
                end_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive end date.' },
                limit: { type: 'integer', minimum: 1, maximum: 50 }
              },
              required: ['query'],
              additionalProperties: false
            }
          },
          {
            name: 'list_entries',
            description: 'List your own entries for a date range, newest first.',
            inputSchema: {
              type: 'object',
              properties: {
                start_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive start date.' },
                end_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive end date.' },
                limit: { type: 'integer', minimum: 1, maximum: 100 }
              },
              additionalProperties: false
            }
          },
          {
            name: 'analyze_entries',
            description: 'Return counts, date coverage, top hashtags, and writing volume summaries over your own entries.',
            inputSchema: {
              type: 'object',
              properties: {
                start_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive start date.' },
                end_date: { type: 'string', description: 'Optional YYYY-MM-DD inclusive end date.' },
                limit: { type: 'integer', minimum: 1, maximum: 25, description: 'How many sample entries or hashtags to include.' }
              },
              additionalProperties: false
            }
          },
          {
            name: 'create_entry',
            description: 'Create a journal entry on a given calendar day (defaults to today in the user account timezone). Plain text is turned into HTML paragraphs. If an entry already exists for that day, appends after a separator (same as the web app) unless merge_with_existing is false.',
            inputSchema: {
              type: 'object',
              properties: {
                date: { type: 'string', description: 'Optional YYYY-MM-DD; omitted means today in the account timezone.' },
                body: { type: 'string', description: 'Entry text (plain text; line breaks become paragraphs). HTML is escaped.' },
                merge_with_existing: {
                  type: 'boolean',
                  description: 'When true (default), append to the existing entry for this date if one exists. When false, return an error if the date is already taken.'
                }
              },
              required: ['body'],
              additionalProperties: false
            }
          }
        ]
      }
    }
  end

  def tools_call_response
    tool_name = params.require(:params).require(:name)
    arguments = params[:params][:arguments] || {}

    result =
      case tool_name
      when 'search_entries'
        search_tool(arguments)
      when 'list_entries'
        list_tool(arguments)
      when 'analyze_entries'
        analyze_tool(arguments)
      when 'create_entry'
        create_entry_tool(arguments)
      else
        return render_mcp_error(code: -32601, message: "Unknown tool: #{tool_name}")
      end

    {
      jsonrpc: '2.0',
      id: params[:id],
      result: {
        content: [
          {
            type: 'text',
            text: JSON.pretty_generate(result)
          }
        ],
        structuredContent: result
      }
    }
  end

  def search_tool(arguments)
    result = entry_search.search(
      query: arguments.fetch('query'),
      limit: arguments['limit'] || 10,
      since: arguments['start_date'],
      until_date: arguments['end_date']
    )

    {
      query: arguments.fetch('query'),
      total_matches: result[:total_matches],
      entries: result[:entries].map { |entry| normalize_entry(entry) }
    }
  end

  def list_tool(arguments)
    result = entry_search.list(
      limit: arguments['limit'] || 20,
      since: arguments['start_date'],
      until_date: arguments['end_date']
    )

    {
      total_entries: result[:total_matches],
      entries: result[:entries].map { |entry| normalize_entry(entry) }
    }
  end

  def analyze_tool(arguments)
    result = entry_search.analyze(
      query: arguments['query'],
      since: arguments['start_date'],
      until_date: arguments['end_date']
    )

    {
      total_entries: result[:total_matches],
      date_range: result[:date_range],
      entry_count_by_year: result[:entry_count_by_year],
      top_hashtags: result[:most_used_hashtags].map { |tag| { hashtag: tag[:tag], count: tag[:count] } },
      average_words_per_entry: result[:average_entry_length_words],
      sample_entries: result[:sample_highlights]
    }
  end

  def create_entry_tool(arguments)
    merge = arguments['merge_with_existing'] != false
    date_str = arguments['date'].presence&.strip
    date_str = mcp_default_entry_date_iso8601 if date_str.blank?

    Mcp::EntryCreator.new(user: @mcp_user).create(
      date_string: date_str,
      body_text: arguments.fetch('body'),
      merge_with_existing: merge
    )
  end

  def mcp_default_entry_date_iso8601
    tz = ActiveSupport::TimeZone[@mcp_user.send_timezone] || Time.zone
    Time.current.in_time_zone(tz).to_date.iso8601
  end

  def entry_search
    @entry_search ||= Mcp::EntrySearch.new(user: @mcp_user)
  end

  def normalize_entry(entry)
    {
      id: entry[:id],
      date: entry[:date],
      excerpt: entry[:text_body].to_s.squish.truncate(400),
      hashtags: entry[:hashtags],
      has_image: entry[:has_image]
    }
  end

  def render_mcp_error(code:, message:)
    render json: { jsonrpc: '2.0', id: params[:id], error: { code: code, message: message } }, status: :ok
  end
end
