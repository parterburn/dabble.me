class AddSongsToEntries < ActiveRecord::Migration[5.0]
  def change
    add_column :entries, :songs, :jsonb, default: [], array:true
  end
end
