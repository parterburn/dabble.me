class RemoveParanoidFromUser < ActiveRecord::Migration[6.1]
  def change
    remove_column :users, :paranoid_verification_code, :string
    remove_column :users, :paranoid_verification_attempt, :integer, default: 0
    remove_column :users, :paranoid_verified_at, :datetime
  end
end
