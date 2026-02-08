class CreateWebauthnCredentials < ActiveRecord::Migration[6.1]
  def change
    create_table :webauthn_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id
      t.string :public_key
      t.string :nickname
      t.bigint :sign_count

      t.timestamps
    end
    add_index :webauthn_credentials, :external_id
  end
end
