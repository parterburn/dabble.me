class AddPlanToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :plan, :string
  end
end
