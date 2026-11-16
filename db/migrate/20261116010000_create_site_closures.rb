# The date Dabble Me closes, once an admin has announced one (SiteClosure).
# No row means the service is open.
class CreateSiteClosures < ActiveRecord::Migration[8.1]
  def change
    create_table :site_closures do |t|
      t.date :closes_on, null: false
      # The admin who announced it. Kept as a bare id so the record outlives the account.
      t.bigint :announced_by_id
      # There is one closure or none.
      t.boolean :singleton, null: false, default: true
      t.timestamps
      t.index :singleton, unique: true
    end
  end
end
