class AddSongsToEntries < ActiveRecord::Migration
  def change
    add_column :entries, :songs, :jsonb, default: []
  end
end
