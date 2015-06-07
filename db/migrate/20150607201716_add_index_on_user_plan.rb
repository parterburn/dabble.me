class AddIndexOnUserPlan < ActiveRecord::Migration
  def change
    add_index(:users, :plan)
  end
end
