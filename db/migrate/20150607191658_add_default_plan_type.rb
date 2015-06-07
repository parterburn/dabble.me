class AddDefaultPlanType < ActiveRecord::Migration
  def change
    change_column :users, :plan, :text, :default => "Free"
  end
end
