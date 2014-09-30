class ChangeDefaultDateColumn < ActiveRecord::Migration
  def change
    change_column :entries, :date, :datetime, :null=>false, :default=>'now()'
  end
end
