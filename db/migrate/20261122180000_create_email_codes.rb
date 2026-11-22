# Six-digit codes emailed for passwordless sign-in and sign-up, and for confirming account
# changes on an account with no password (EmailCode). The address is kept only as a keyed
# digest, so the table never holds the email of someone who typed it and never signed up.
# users.email_verified_at: when a code sent to the account's address was last entered.
class CreateEmailCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :email_codes do |t|
      t.string :purpose, null: false
      t.string :email_digest, null: false
      t.references :user, foreign_key: { on_delete: :cascade }, index: true
      t.string :code_digest, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.datetime :created_at, null: false
    end
    add_index :email_codes, %i[email_digest purpose created_at]
    add_index :email_codes, :expires_at

    add_column :users, :email_verified_at, :datetime
  end
end
