# Holds the single row EncryptionCheck uses to confirm a process's keys.
class CreateEncryptionChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :encryption_checks do |t|
      t.text :value, null: false
      t.text :lookup, null: false
      # Always true, and unique, so the table can never hold a second row.
      t.boolean :singleton, null: false, default: true, index: { unique: true }
      t.timestamps
    end
  end
end
