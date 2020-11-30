class CreateLabels < ActiveRecord::Migration[6.0]
  def change
    create_table :labels do |t|
      t.string :label
      t.integer :entry_id, null: false

      t.timestamps
    end
  end
end
