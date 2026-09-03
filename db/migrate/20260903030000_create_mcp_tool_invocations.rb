class CreateMcpToolInvocations < ActiveRecord::Migration[6.1]
  def change
    create_table :mcp_tool_invocations do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :tool_name, null: false
      t.string :source, null: false, default: 'oauth'
      t.boolean :success, null: false, default: true
      t.integer :result_count
      t.integer :duration_ms
      t.bigint :oauth_application_id
      t.datetime :created_at, null: false
    end

    add_index :mcp_tool_invocations, :created_at
    add_index :mcp_tool_invocations, [:tool_name, :created_at]
    add_index :mcp_tool_invocations, [:user_id, :created_at]
    add_index :mcp_tool_invocations, [:source, :created_at]
    add_index :mcp_tool_invocations, :oauth_application_id

    add_column :business_metric_snapshots, :mcp_connected_users, :integer, null: false, default: 0
    add_column :business_metric_snapshots, :mcp_active_users_7d, :integer, null: false, default: 0
    add_column :business_metric_snapshots, :mcp_active_users_30d, :integer, null: false, default: 0
    add_column :business_metric_snapshots, :mcp_tool_calls, :integer, null: false, default: 0
    add_column :business_metric_snapshots, :mcp_tool_breakdown, :jsonb, null: false, default: {}
  end
end
