class AddDeviseSecurity < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :paranoid_verification_code, :string
    add_column :users, :paranoid_verification_attempt, :integer, default: 0
    add_column :users, :paranoid_verified_at, :datetime
    add_index(:users, :paranoid_verification_code)
    add_index(:users, :paranoid_verified_at)
  end
end
