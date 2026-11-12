# A requested export of someone's entries: a ZIP kept in private storage for
# a week and downloaded through the app after signing in.
class CreateExports < ActiveRecord::Migration[8.1]
  def change
    create_table :exports do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      # Names the export in its link. Random, so links can't be guessed.
      t.string :token, null: false, index: { unique: true }
      t.string :status, null: false, default: "preparing"
      # What it holds: "all", "year:2021" or "search". Never the search words.
      t.string :scope, null: false, default: "all"
      # Where the ZIP is in storage. Cleared once the file is deleted.
      t.string :storage_key
      t.integer :entry_count, null: false, default: 0
      t.integer :image_count, null: false, default: 0
      t.integer :skipped_image_count, null: false, default: 0
      t.bigint :byte_size
      t.datetime :expires_at
      t.datetime :downloaded_at
      t.integer :download_count, null: false, default: 0
      t.timestamps
      t.index :expires_at
    end
  end
end
