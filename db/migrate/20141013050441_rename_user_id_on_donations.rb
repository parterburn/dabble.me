class RenameUserIdOnDonations < ActiveRecord::Migration
  def change
    rename_column :donations, :user_id_id, :user_id
  end
end
