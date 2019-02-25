class AddPayhereIdToUser < ActiveRecord::Migration
  def change
    add_column :users, :payhere_id, :string
  end
end
