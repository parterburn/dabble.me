# frozen_string_literal: true

module Mcp
  module DabbleServer
    TOOLS = [
      Tools::SearchEntries,
      Tools::ListEntries,
      Tools::AnalyzeEntries,
      Tools::GetImageUploadUrl,
      Tools::CreateEntry
    ].freeze

    def self.build_for_user(user)
      site = ApplicationHelper.site_public_base_url
      MCP::Server.new(
        name: 'dabble-me',
        title: 'Dabble Me Journal',
        version: '1.0.0',
        instructions: 'Dabble Me is a private personal journal MCP server. Use these tools only when the user clearly ' \
                      'intends to read, search, reflect on, analyze, or write their own Dabble Me journal after OAuth. ' \
                      'Users may call it their journal, diary, daily log, reflections, memories, notes, or entries. ' \
                      'Typical requests include “summarize my journal from last month,” “find every time I mentioned ' \
                      'burnout,” “what patterns do you notice in my writing?”, and “add this reflection to today’s journal.” ' \
                      'Choose search_entries for a topic or phrase, list_entries for a time period, analyze_entries for ' \
                      'counts and writing patterns, and create_entry only when the user asks to save something. ' \
                      'Do not use these tools for fictional writing, scholarly journals, another journal product, or ' \
                      'general advice that does not require the user’s stored Dabble Me data. ' \
                      'For user-uploaded or local images, prefer get_image_upload_url first so the client can upload bytes directly; ' \
                      'then pass uploaded_image_key to create_entry. Use image_base64 only as a small-image fallback. ' \
                      'Tools always apply to the signed-in account from OAuth and cannot access other users’ data. ' \
                      'Reading sends selected journal content to the connected AI client for processing. Never claim a ' \
                      'write succeeded unless create_entry returns success. ' \
                      "When linking to a day in the web app, use #{site}/entries/YYYY/M/D with unpadded month and day " \
                      "(example: #{site}/entries/2026/4/21). The compose page for new entries is #{site}/write .",
        tools: TOOLS,
        server_context: { user_id: user.id }
      )
    end
  end
end
