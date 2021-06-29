class AddNewFrequencyField < ActiveRecord::Migration[6.0]
  def change
    change_column :users, :frequency, :text, array: true, default: ["Sun"], null: true
  end
end
