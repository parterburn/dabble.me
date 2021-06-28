class ChangdDefaultOnSendTimeOnUsersTable < ActiveRecord::Migration[4.2]
  def change
    change_column :users, :send_time, :time, :null=>false, :default=>"20:00:00"
    change_column :users, :frequency, :text, :default => ["Mon","Wed","Fri"], :array => true
  end
end
