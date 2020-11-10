class AddFilterToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :past_filter, :string
  end
end
