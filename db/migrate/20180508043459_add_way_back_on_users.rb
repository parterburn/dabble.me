class AddWayBackOnUsers < ActiveRecord::Migration
  def change
    add_column :users, :way_back_past_entries, :boolean, :default => true
  end
end
