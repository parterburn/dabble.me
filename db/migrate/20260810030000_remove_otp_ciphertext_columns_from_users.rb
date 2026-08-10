class RemoveOtpCiphertextColumnsFromUsers < ActiveRecord::Migration[6.1]
  def up
    remove_column :users, :otp_auth_secret_ciphertext, if_exists: true
    remove_column :users, :otp_recovery_secret_ciphertext, if_exists: true
    remove_column :users, :otp_persistence_seed_ciphertext, if_exists: true
  end

  def down
    add_column :users, :otp_auth_secret_ciphertext, :text, if_not_exists: true
    add_column :users, :otp_recovery_secret_ciphertext, :text, if_not_exists: true
    add_column :users, :otp_persistence_seed_ciphertext, :text, if_not_exists: true
  end
end
