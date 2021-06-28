class AddSongsToEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :songs, :jsonb, default: [], array:true
  end
end
