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
        instructions: 'Use these tools only when the user wants something done with their own journal on Dabble Me ' \
                      '(dabble.me) after OAuth. Users often say diary, daily log, reflections, notes, or entries to ' \
                      'mean the same saved writing in their account—use tools when they clearly mean that data, ' \
                      'not creative writing or generic prompts. Capabilities: search or list saved posts, analyze ' \
                      'their writing, or add a new entry. Do not use for fictional scenes, scholarly journals, other products, ' \
                      'or advice that does not require their stored Dabble Me data. ' \
                      'Tools always apply to the signed-in account from OAuth and cannot access other users’ data. ' \
                      "When linking to a day in the web app, use #{site}/entries/YYYY/M/D with unpadded month and day " \
                      "(example: #{site}/entries/2026/4/21). The compose page for new entries is #{site}/write .",
        tools: TOOLS,
        server_context: { user_id: user.id }
      )
    end
  end
end
