class AddRaindropApiKeyToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :raindrop_api_key, :string
  end
end
