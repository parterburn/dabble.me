class AddBounceCountToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :emails_bounced, :integer, :default => 0
  end
end
