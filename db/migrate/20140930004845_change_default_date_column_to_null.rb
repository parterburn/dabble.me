class ChangeDefaultDateColumnToNull < ActiveRecord::Migration[4.2]
  def change
    change_column :entries, :date, :datetime, :null=>false, :default=>nil
  end
end
