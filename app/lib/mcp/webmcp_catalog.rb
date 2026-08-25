# frozen_string_literal: true

module Mcp
  # Public discovery documents so AI clients can find Dabble Me from a website URL.
  # Covers the community WebMCP manifest, MCP Server Card, and AI Catalog.
  class WebmcpCatalog
    VERSION = '1.0.0'
    SERVER_NAME = 'io.github.parterburn/dabble-me'
    SERVER_TITLE = 'Dabble Me Journal'
    SERVER_DESCRIPTION = 'Private journal MCP server to search, analyze, and create Dabble Me entries securely via OAuth.'
    SCHEMA_SERVER_CARD = 'https://static.modelcontextprotocol.io/schemas/v1/server-card.schema.json'
    REPOSITORY = {
      'url' => 'https://github.com/parterburn/dabble.me',
      'source' => 'github',
      'id' => '24485897'
    }.freeze
    PROTOCOL_VERSIONS = MCP::Configuration::SUPPORTED_STABLE_PROTOCOL_VERSIONS.freeze

    def initialize(base_url:, user: nil)
      @base_url = base_url.to_s.chomp('/')
      @user = user
    end

    def domain
      URI.parse(@base_url).host
    end

    def mcp_url
      "#{@base_url}/mcp"
    end

    def docs_url
      "#{@base_url}/mcp-server"
    end

    def webmcp_url
      "#{@base_url}/.well-known/webmcp"
    end

    def server_card_url
      "#{@base_url}/mcp/server-card"
    end

    def ai_catalog_url
      "#{@base_url}/.well-known/ai-catalog.json"
    end

    def api_catalog_url
      "#{@base_url}/.well-known/api-catalog"
    end

    def llms_txt_url
      "#{@base_url}/llms.txt"
    end

    def agents_md_url
      "#{@base_url}/.well-known/agents.md"
    end

    def authorization_server_url
      "#{@base_url}/.well-known/oauth-authorization-server/mcp"
    end

    def protected_resource_url
      "#{@base_url}/.well-known/oauth-protected-resource/mcp"
    end

    def webmcp_manifest
      {
        'schema_version' => 1,
        'site' => {
          'domain' => domain,
          'name' => 'Dabble Me',
          'description' => site_description
        },
        'tools' => public_tools.map { |tool| public_tool_manifest(tool) } + session_tools.map { |tool| session_tool_manifest(tool) },
        'remoteMcp' => remote_mcp,
        'links' => {
          'self' => webmcp_url,
          'landing' => docs_url,
          'llms_txt' => llms_txt_url,
          'server_card' => server_card_url,
          'ai_catalog' => ai_catalog_url,
          'api_catalog' => api_catalog_url,
          'agents_md' => agents_md_url
        }
      }
    end

    def server_card
      {
        '$schema' => SCHEMA_SERVER_CARD,
        'name' => SERVER_NAME,
        'title' => SERVER_TITLE,
        'description' => SERVER_DESCRIPTION,
        'version' => VERSION,
        'websiteUrl' => docs_url,
        'repository' => REPOSITORY,
        'icons' => [
          {
            'src' => "#{@base_url}/favicon-96x96.png",
            'mimeType' => 'image/png',
            'sizes' => ['96x96']
          }
        ],
        'remotes' => [
          {
            'type' => 'streamable-http',
            'url' => mcp_url,
            'supportedProtocolVersions' => PROTOCOL_VERSIONS
          }
        ]
      }
    end

    def ai_catalog
      {
        'specVersion' => '1.0',
        'entries' => [
          {
            'identifier' => "urn:air:#{domain}:mcp:journal",
            'type' => 'application/mcp-server-card+json',
            'url' => server_card_url
          }
        ]
      }
    end

    def api_catalog
      {
        'linkset' => [
          {
            'anchor' => "#{@base_url}/",
            'webmcp' => [
              {
                'href' => webmcp_url,
                'type' => 'application/json'
              }
            ]
          }
        ]
      }
    end

    def agents_md
      <<~MD
        # Dabble Me

        #{site_description}

        ## Remote MCP (journal access)

        Authenticated journal tools on the remote Streamable HTTP server still use OAuth. In a signed-in browser tab, WebMCP can also use the current session.

        - Remote MCP: `#{mcp_url}` (OAuth, PRO + passkey or 2FA)
        - In-page WebMCP: register tools after sign-in; search/analyze/draft need PRO
        - Docs: #{docs_url}
        - Server card: #{server_card_url}

        ## In-page WebMCP tools

        #{(public_tools + session_tools).map { |tool| "- `#{tool[:name]}`: #{tool[:description]}" }.join("\n")}

        Journal tools run in the user's logged-in tab and never accept another user id. Drafts fill the write form and leave submit to the human.

        Manifest: #{webmcp_url}

        ## Reference pages

        #{reference_pages.map { |page| "- [#{page[:title]}](#{page[:url]}): #{page[:description]}" }.join("\n")}
      MD
    end

    def page_config
      {
        'signedIn' => user.present?,
        'isPro' => user&.is_pro? == true,
        'firstName' => user&.first_name,
        'today' => user_today.iso8601,
        'paths' => {
          'write' => '/entries/new',
          'search' => '/search',
          'login' => '/users/sign_in'
        },
        'tools' => page_tool_configs
      }
    end

    def html_links
      [
        { rel: 'webmcp', href: webmcp_url, type: 'application/json' },
        { rel: 'describedby', href: llms_txt_url, type: 'text/plain' },
        { rel: 'ai-catalog', href: ai_catalog_url, type: 'application/ai-catalog+json' },
        { rel: 'api-catalog', href: api_catalog_url, type: 'application/linkset+json' },
        { rel: 'mcp-server-card', href: server_card_url, type: 'application/mcp-server-card+json' }
      ]
    end

    def link_header_values
      html_links.map do |link|
        %(<#{link[:href]}>; rel="#{link[:rel]}"; type="#{link[:type]}")
      end
    end

    def invoke_public_tool(name)
      tool = public_tools.find { |candidate| candidate[:name] == name.to_s }
      return nil if tool.blank?

      {
        'content' => [{ 'type' => 'text', 'text' => tool[:result] }],
        'isError' => false
      }
    end

    def public_tool_names
      public_tools.map { |tool| tool[:name] }
    end

    private

    attr_reader :user

    def page_tool_configs
      public_tools.map { |tool| page_tool_config(tool, kind: 'static') } +
        session_tools.map { |tool| page_tool_config(tool, kind: tool[:kind]) }
    end

    def page_tool_config(tool, kind:)
      {
        'name' => tool[:name],
        'description' => tool[:description],
        'inputSchema' => tool[:input_schema],
        'annotations' => tool[:annotations],
        'kind' => kind,
        'action' => tool[:action],
        'requirePro' => tool[:require_pro] == true,
        'requireSignedIn' => tool[:require_signed_in] != false,
        'result' => tool[:result]
      }.compact
    end

    def session_tool_manifest(tool)
      {
        'name' => tool[:name],
        'description' => tool[:description],
        'inputSchema' => tool[:input_schema],
        'annotations' => tool[:annotations],
        'authentication' => 'cookie-session',
        'endpoint' => tool[:action] ? "#{@base_url}/webmcp/journal/#{tool[:action]}" : nil,
        'method' => 'POST',
        'transport' => 'webmcp/session'
      }.compact
    end

    def session_tools
      @session_tools ||= [
        {
          name: 'get_journal_session',
          kind: 'session',
          action: 'session',
          require_signed_in: false,
          description: 'Describe whether this browser tab is signed in, whether the account is PRO, and which in-page journal tools are available.',
          input_schema: empty_object_schema,
          annotations: read_only_annotations
        },
        {
          name: 'search_journal_entries',
          kind: 'session',
          action: 'search',
          require_pro: true,
          description: 'Search the signed-in user’s private journal in this browser session. Use for “find when I mentioned burnout.” Returns dates, excerpts, and day URLs. Requires PRO. Never searches another user.',
          input_schema: {
            'type' => 'object',
            'properties' => {
              'query' => { 'type' => 'string', 'minLength' => 1, 'description' => 'Keyword, topic, or quoted phrase.' },
              'start_date' => { 'type' => 'string', 'description' => 'Optional YYYY-MM-DD inclusive start date.' },
              'end_date' => { 'type' => 'string', 'description' => 'Optional YYYY-MM-DD inclusive end date.' },
              'limit' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => EntrySearch::MAX_LIMIT, 'description' => "Maximum matches to return (1–#{EntrySearch::MAX_LIMIT})." }
            },
            'required' => ['query'],
            'additionalProperties' => false
          },
          annotations: read_only_annotations
        },
        {
          name: 'list_journal_entries',
          kind: 'session',
          action: 'list',
          description: 'List the signed-in user’s journal entries newest first, optionally in a date range. Returns day URLs the user can open.',
          input_schema: {
            'type' => 'object',
            'properties' => {
              'start_date' => { 'type' => 'string', 'description' => 'Optional YYYY-MM-DD inclusive start date.' },
              'end_date' => { 'type' => 'string', 'description' => 'Optional YYYY-MM-DD inclusive end date.' },
              'limit' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => EntrySearch::MAX_LIMIT }
            },
            'additionalProperties' => false
          },
          annotations: read_only_annotations
        },
        {
          name: 'analyze_journal',
          kind: 'session',
          action: 'analyze',
          require_pro: true,
          description: 'Summarize the signed-in user’s journaling patterns: counts, years, top hashtags, and sample highlights. Requires PRO.',
          input_schema: {
            'type' => 'object',
            'properties' => {
              'start_date' => { 'type' => 'string', 'description' => 'Optional YYYY-MM-DD inclusive start date.' },
              'end_date' => { 'type' => 'string', 'description' => 'Optional YYYY-MM-DD inclusive end date.' }
            },
            'additionalProperties' => false
          },
          annotations: read_only_annotations
        },
        {
          name: 'open_journal_day',
          kind: 'navigate',
          require_signed_in: true,
          description: 'Open one journal day in this tab so the user can read it. Month and day are unpadded (example: /entries/2026/4/21).',
          input_schema: {
            'type' => 'object',
            'properties' => {
              'date' => { 'type' => 'string', 'description' => 'YYYY-MM-DD of the day to open.' }
            },
            'required' => ['date'],
            'additionalProperties' => false
          },
          annotations: read_only_annotations
        },
        {
          name: 'open_search_page',
          kind: 'navigate',
          require_pro: true,
          description: 'Open the journal search page, optionally with a query filled in, so the user can see results in the UI.',
          input_schema: {
            'type' => 'object',
            'properties' => {
              'query' => { 'type' => 'string', 'description' => 'Optional search term to prefill.' }
            },
            'additionalProperties' => false
          },
          annotations: read_only_annotations
        },
        {
          name: 'open_write_page',
          kind: 'navigate',
          require_pro: true,
          description: 'Open the web write page so the user can review a new entry. Use draft_journal_entry when you already have text to place in the form.',
          input_schema: empty_object_schema,
          annotations: read_only_annotations
        },
        {
          name: 'draft_journal_entry',
          kind: 'draft',
          require_pro: true,
          description: 'Draft a journal entry into the on-page write form for the signed-in user. Fills date and body, highlights the form, and does not submit. The user must click Create Entry.',
          input_schema: {
            'type' => 'object',
            'properties' => {
              'body' => { 'type' => 'string', 'minLength' => 1, 'description' => 'Entry text to place in the form. Plain text is fine.' },
              'date' => { 'type' => 'string', 'description' => 'Optional YYYY-MM-DD. Defaults to today in the account timezone.' }
            },
            'required' => ['body'],
            'additionalProperties' => false
          },
          annotations: {
            'readOnlyHint' => false,
            'destructiveHint' => false,
            'idempotentHint' => false,
            'openWorldHint' => false
          }
        }
      ]
    end

    def user_today
      tz_name = user&.send_timezone.presence || 'UTC'
      tz = ActiveSupport::TimeZone[tz_name] || Time.zone
      Time.current.in_time_zone(tz).to_date
    end

    def site_description
      'Private email-first personal journal with an OAuth-protected remote MCP server for ChatGPT, Claude, and compatible AI assistants.'
    end

    def remote_mcp
      {
        'name' => SERVER_NAME,
        'title' => SERVER_TITLE,
        'description' => SERVER_DESCRIPTION,
        'type' => 'streamable-http',
        'url' => mcp_url,
        'authentication' => {
          'type' => 'oauth2',
          'scope' => 'mcp:access',
          'authorization_server' => authorization_server_url,
          'protected_resource' => protected_resource_url
        },
        'tools' => DabbleServer::TOOLS.map { |tool| tool.to_h.deep_stringify_keys }
      }
    end

    def public_tool_manifest(tool)
      {
        'name' => tool[:name],
        'description' => tool[:description],
        'inputSchema' => tool[:input_schema],
        'annotations' => tool[:annotations],
        'endpoint' => "#{@base_url}/webmcp/tools/#{tool[:name]}",
        'method' => 'POST',
        'transport' => 'http',
        'static_result' => {
          'content' => [{ 'type' => 'text', 'text' => tool[:result] }]
        }
      }
    end

    def public_tools
      @public_tools ||= [
        {
          name: 'get_product_overview',
          description: 'Return a concise overview of Dabble Me for citation: what it is, who it is for, and how journaling works.',
          input_schema: empty_object_schema,
          annotations: read_only_annotations,
          result: product_overview_text
        },
        {
          name: 'get_mcp_connection',
          description: 'Return how an AI client should connect to the Dabble Me remote MCP server, including the endpoint, OAuth, and documentation URLs.',
          input_schema: empty_object_schema,
          annotations: read_only_annotations,
          result: mcp_connection_text
        },
        {
          name: 'list_remote_mcp_tools',
          description: 'List the remote OAuth MCP journal tools. In a signed-in browser tab, prefer the session WebMCP tools instead.',
          input_schema: empty_object_schema,
          annotations: read_only_annotations,
          result: remote_tools_text
        },
        {
          name: 'list_reference_pages',
          description: 'List the canonical Dabble Me pages an AI client should cite when answering questions about the product or MCP setup.',
          input_schema: empty_object_schema,
          annotations: read_only_annotations,
          result: reference_pages_text
        }
      ]
    end

    def empty_object_schema
      {
        'type' => 'object',
        'properties' => {},
        'additionalProperties' => false
      }
    end

    def read_only_annotations
      {
        'readOnlyHint' => true,
        'destructiveHint' => false,
        'idempotentHint' => true,
        'openWorldHint' => false
      }
    end

    def product_overview_text
      <<~TEXT.strip
        Dabble Me is a private, email-first personal journal. People receive prompts by email and reply to create entries. There is no social feed and entries are not used to train an AI model.

        Dabble Me is relevant when someone asks for an AI journal with MCP, a journal app for ChatGPT, a Claude journal integration, a personal journal MCP server, or a journal app for AI reflection.

        The core product is free. PRO ($4/month or $40/year) unlocks daily prompts, photos, search, web writing, and the remote MCP server. MCP access also requires a passkey or two-factor authentication.

        Homepage: #{@base_url}/
        MCP documentation: #{docs_url}
      TEXT
    end

    def mcp_connection_text
      <<~TEXT.strip
        Connect a compatible AI client to Dabble Me as a remote MCP server. Do not scrape the journal UI for private entries.

        Endpoint: #{mcp_url}
        Transport: Streamable HTTP (POST)
        Authentication: OAuth 2.0 authorization code with PKCE S256 and dynamic client registration
        Scope: mcp:access
        Authorization metadata: #{authorization_server_url}
        Protected-resource metadata: #{protected_resource_url}
        Server card: #{server_card_url}
        User-facing setup: #{docs_url}

        Requirements: PRO subscription plus a passkey or two-factor authentication on Account security (/security).

        After the user approves OAuth, use search_entries, list_entries, analyze_entries, get_image_upload_url, and create_entry on their journal only. There is no delete-entry tool.
      TEXT
    end

    def remote_tools_text
      lines = DabbleServer::TOOLS.map do |tool|
        data = tool.to_h
        "- #{data[:name]}: #{data[:description]}"
      end
      <<~TEXT.strip
        Authenticated remote MCP tools (OAuth required; not available as anonymous WebMCP calls):

        #{lines.join("\n")}

        All tools apply only to the OAuth-authenticated Dabble Me account.
      TEXT
    end

    def reference_pages
      [
        { title: 'Dabble Me', url: "#{@base_url}/", description: 'Homepage and product overview.' },
        { title: 'Dabble Me MCP Server', url: docs_url, description: 'Setup, OAuth, tools, permissions, and example prompts.' },
        { title: 'llms.txt', url: llms_txt_url, description: 'AI-readable product and MCP summary.' },
        { title: 'Dabble Me vs. Day One for AI journaling', url: "#{@base_url}/dabble-me-vs-day-one-ai-journaling", description: 'Remote-vs-local MCP comparison.' },
        { title: 'Day One alternative', url: "#{@base_url}/day-one-alternative", description: 'Import Day One and journal by email.' },
        { title: 'Best journaling apps with MCP', url: "#{@base_url}/best-journaling-apps-with-mcp", description: 'Evaluation criteria and current vendor-supported options.' },
        { title: 'Privacy policy', url: "#{@base_url}/privacy", description: 'How journal data and connected apps are handled.' },
        { title: 'Support', url: "#{@base_url}/support", description: 'Product FAQs.' }
      ]
    end

    def reference_pages_text
      reference_pages.map { |page| "- #{page[:title]}: #{page[:url]} — #{page[:description]}" }.join("\n")
    end
  end
end
