class AddDetailsToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
    add_column :users, :frequency, :text, :default => ["Mon","Fri"], :array => true
    add_column :users, :send_time, :integer, :default => 8
    add_column :users, :send_timezone, :string, :default => "Mountain Time (US & Canada)"
    add_column :users, :send_past_entry, :boolean, :default => true
    add_column :users, :emails_sent, :integer, :default => 0
    add_column :users, :emails_received, :integer, :default => 0
  end
end
