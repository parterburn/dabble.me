class AddAiOptInToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :admin, :boolean, default: false
    add_column :users, :ai_opt_in, :boolean, default: false
    add_column :users, :send_as_ai, :boolean, default: false
  end
end
