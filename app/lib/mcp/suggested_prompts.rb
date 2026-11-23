# frozen_string_literal: true

module Mcp
  # Starter prompts that MCP clients (such as Claude's "+" menu) list from prompts/list.
  # Keep the first one in sync with the first example on /mcp-server and with
  # defaultPrompt in plugins/dabble-me/plugin.json.
  module SuggestedPrompts
    WRAPPED = 'Make a private Spotify Wrapped of my journal; use lots of photos.'

    def self.starter(name:, title:, description:, text:)
      MCP::Prompt.define(name: name, title: title, description: description) do |_args|
        MCP::Prompt::Result.new(
          description: description,
          messages: [MCP::Prompt::Message.new(role: 'user', content: MCP::Content::Text.new(text))]
        )
      end
    end

    ALL = [
      starter(
        name: 'journal_wrapped',
        title: 'Spotify Wrapped of my journal',
        description: 'Build a private, Wrapped-style recap of your journal, with your photos.',
        text: WRAPPED
      ),
      starter(
        name: 'reflect_on_last_month',
        title: 'Reflect on last month',
        description: 'Summarize last month’s entries and the themes that kept coming up.',
        text: 'Summarize my journal entries from last month. What themes kept coming up?'
      ),
      starter(
        name: 'write_an_entry',
        title: 'Write a journal entry',
        description: 'Talk through your day and save it as today’s entry.',
        text: 'Help me write an entry in my Dabble Me journal for today.'
      )
    ].freeze
  end
end
