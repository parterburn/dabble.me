class AddDefaultPlanType < ActiveRecord::Migration[4.2]
  def change
    change_column :users, :plan, :text, :default => "Free"
  end
end
