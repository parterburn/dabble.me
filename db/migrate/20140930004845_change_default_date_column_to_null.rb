class ChangeDefaultDateColumnToNull < ActiveRecord::Migration
  def change
    change_column :entries, :date, :datetime, :null=>false, :default=>nil
  end
end
