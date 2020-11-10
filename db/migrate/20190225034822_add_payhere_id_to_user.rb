class AddPayhereIdToUser < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :payhere_id, :string
  end
end
