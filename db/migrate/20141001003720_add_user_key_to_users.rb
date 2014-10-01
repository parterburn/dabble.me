class AddUserKeyToUsers < ActiveRecord::Migration
  def change
    add_column :users, :user_key, :string
    add_index :users, :user_key, unique: true
  end
end