# frozen_string_literal: true

class RemoveLegacyMcpTokenFromUsers < ActiveRecord::Migration[6.1]
  def change
    remove_index :users, :mcp_token_digest, if_exists: true
    remove_column :users, :mcp_enabled, :boolean
    remove_column :users, :mcp_token_digest, :string
    remove_column :users, :mcp_token_generated_at, :datetime
    remove_column :users, :mcp_last_used_at, :datetime
    remove_column :users, :mcp_token_expires_at, :datetime
  end
end
