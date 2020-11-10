class RenameUserIdOnDonations < ActiveRecord::Migration[4.2]
  def change
    rename_column :donations, :user_id_id, :user_id
  end
end
