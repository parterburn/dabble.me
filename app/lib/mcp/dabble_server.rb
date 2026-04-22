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
      MCP::Server.new(
        name: 'dabble-me',
        title: 'Dabble Me',
        version: '1.0.0',
        instructions: 'Journal tools always apply to the signed-in Dabble Me account that completed OAuth. ' \
                      'They cannot access other users’ data.',
        tools: TOOLS,
        server_context: { user_id: user.id }
      )
    end
  end
end
