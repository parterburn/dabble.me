class CreateEntriesLabels < ActiveRecord::Migration[6.0]
  def change
    create_table :entries_labels do |t|
      t.references :entry, foreign_key: true
      t.references :label, foreign_key: true
    end
  end
end
