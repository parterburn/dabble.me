class AddIndexOnUserPlan < ActiveRecord::Migration[4.2]
  def change
    add_index(:users, :plan)
  end
end
