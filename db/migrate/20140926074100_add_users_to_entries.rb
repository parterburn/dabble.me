class AddUsersToEntries < ActiveRecord::Migration
  def change
    change_table :entries do |t|
      t.references :user, index: true
    end
  end
  def down
    change_table :entries do |t|
      t.remove :user_id
    end
  end
end
