class ChangeDefaultDateColumnToNull3 < ActiveRecord::Migration[4.2]
  def change
    change_column :entries, :date, :datetime, :default=>nil
  end
end
