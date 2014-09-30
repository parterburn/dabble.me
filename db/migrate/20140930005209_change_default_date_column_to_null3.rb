class ChangeDefaultDateColumnToNull3 < ActiveRecord::Migration
  def change
    change_column :entries, :date, :datetime, :default=>nil
  end
end
