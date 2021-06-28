class ChangeDefaultFrequency < ActiveRecord::Migration[4.2]
  def change
    change_column :users, :frequency, :text, :default => ["Sun"]
  end
end
