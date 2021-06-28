class AddAffiliateTrackingToUsers < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :referrer, :string
  end
end
