# /admin/inspirations counts each inspiration's entries, and with no index on the column
# every one of those was a read of the whole entries table.
class AddInspirationIndexToEntries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :entries, :inspiration_id, algorithm: :concurrently, if_not_exists: true
  end
end
