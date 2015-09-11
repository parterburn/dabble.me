class AddGumroadIdToUsers < ActiveRecord::Migration
  def change
    add_column :users, :gumroad_id, :string
  end
end
