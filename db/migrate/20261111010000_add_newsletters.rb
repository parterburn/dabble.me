# Lets people opt out of product updates separately from their journal
# prompts, and records which newsletter each person was sent.
class AddNewsletters < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :send_updates, :boolean, null: false, default: true
    # People who turned every journal email off asked for no email at all.
    execute "UPDATE users SET send_updates = FALSE WHERE frequency = '{}' OR frequency IS NULL"

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
