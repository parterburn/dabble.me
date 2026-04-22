# frozen_string_literal: true

module Mcp
  module DabbleServer
    TOOLS = [
      Tools::SearchEntries,
      Tools::ListEntries,
      Tools::AnalyzeEntries,
      Tools::CreateEntry
    ].freeze

    def self.build_for_user(user)
      site = ApplicationHelper.site_public_base_url
      MCP::Server.new(
        name: 'dabble-me',
        title: 'Dabble Me',
        version: '1.0.0',
        instructions: 'Journal tools always apply to the signed-in Dabble Me account that completed OAuth. ' \
                      'They cannot access other users’ data. ' \
                      "When pointing the user to a day in the web app, use #{site}/entries/YYYY/M/D with unpadded " \
                      "month and day (example: #{site}/entries/2026/4/21). The web compose page for new entries " \
                      "is #{site}/write .",
        tools: TOOLS,
        server_context: { user_id: user.id }
      )
    end
  end
end
