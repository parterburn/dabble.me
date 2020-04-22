class AddLockableToDevise < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :failed_attempts, :string, default: 0, null: false
    add_column :users, :unlock_token, :string
    add_column :users, :locked_at, :datetime
  end
end
