class AddFilterToUsers < ActiveRecord::Migration
  def change
    add_column :users, :past_filter, :string
  end
end
