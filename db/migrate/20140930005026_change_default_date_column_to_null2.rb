class ChangeDefaultDateColumnToNull2 < ActiveRecord::Migration[4.2]
  def change
    change_column :entries, :date, :datetime
  end
end
