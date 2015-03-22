class ChangeDefaultFrequency < ActiveRecord::Migration
  def change
    change_column :users, :frequency, :text, :default => ["Sun"]
  end
end
