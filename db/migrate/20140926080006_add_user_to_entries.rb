class AddUserToEntries < ActiveRecord::Migration
  def change
    change_table :entries do |t|
      t.remove :user_id
      t.remove :users_id
    end    
    add_reference :entries, :user, index: true
  end
end
