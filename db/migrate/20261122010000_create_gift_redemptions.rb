# A year of PRO given through a gift link (dabble.me/gift/<code>, see Gift). One per account,
# so a shared code can't be redeemed again to stretch the year; the code is kept so a
# capped code can count its redemptions.
class CreateGiftRedemptions < ActiveRecord::Migration[8.1]
  def change
    create_table :gift_redemptions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.string :code, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :gift_redemptions, :code
  end
end
