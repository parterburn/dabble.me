class AddMcpAccessToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :mcp_enabled, :boolean, default: false, null: false
    add_column :users, :mcp_token_digest, :string
    add_column :users, :mcp_token_generated_at, :datetime
    add_column :users, :mcp_last_used_at, :datetime

    add_index :users, :mcp_token_digest, unique: true, where: 'mcp_token_digest IS NOT NULL'
  end
end
