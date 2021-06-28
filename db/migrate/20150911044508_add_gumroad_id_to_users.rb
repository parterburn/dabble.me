class AddGumroadIdToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :gumroad_id, :string
  end
end
