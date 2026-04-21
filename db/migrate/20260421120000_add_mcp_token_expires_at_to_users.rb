class AddMcpTokenExpiresAtToUsers < ActiveRecord::Migration[6.1]
  def up
    add_column :users, :mcp_token_expires_at, :datetime

    execute(<<~SQL.squish)
      UPDATE users
      SET mcp_token_expires_at = mcp_token_generated_at + interval '6 months'
      WHERE mcp_token_digest IS NOT NULL
        AND mcp_token_generated_at IS NOT NULL
    SQL
  end

  def down
    remove_column :users, :mcp_token_expires_at
  end
end
