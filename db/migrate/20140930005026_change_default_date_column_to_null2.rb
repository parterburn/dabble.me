class ChangeDefaultDateColumnToNull2 < ActiveRecord::Migration
  def change
    change_column :entries, :date, :datetime
  end
end
