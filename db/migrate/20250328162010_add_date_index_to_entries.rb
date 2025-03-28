class AddDateIndexToEntries < ActiveRecord::Migration[6.1]
  def change
    add_index :entries, [:user_id, :date], order: { date: :desc }
  end
end
