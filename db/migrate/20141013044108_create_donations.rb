class CreateDonations < ActiveRecord::Migration
  def change
    create_table :donations do |t|
      t.references :user_id, index: true
      t.decimal :amount, :precision => 8, :scale => 2, :default => 0
      t.text :comments
      t.datetime :date
      t.timestamps
    end
  end
end
