# Lets people opt out of product updates separately from their journal
# prompts, and records which newsletter each person was sent.
class AddNewsletters < ActiveRecord::Migration[8.1]
  def up
    # On for everyone, including people who turned their journal emails off:
    # that setting is about prompts, and this one is about updates.
    add_column :users, :send_updates, :boolean, null: false, default: true

    create_table :newsletter_deliveries do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :newsletter, null: false
      t.string :variant, null: false
      t.datetime :created_at, null: false
      # One copy of a newsletter per person, however often the send is run.
      t.index %i[user_id newsletter], unique: true
      t.index :newsletter
    end
  end

  def down
    drop_table :newsletter_deliveries
    remove_column :users, :send_updates
  end
end
