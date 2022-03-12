class AddOriginalEmailToEntries < ActiveRecord::Migration[6.0]
  def change
    add_column :entries, :original_email, :jsonb, null: true, default: {}
  end
end
