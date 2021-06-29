class RenameFrequencyFields < ActiveRecord::Migration[6.0]
  def change
    remove_column :users, :frequency
    rename_column :users, :frequency_upd, :frequency
  end
end
