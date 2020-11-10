class CreateInspirationsTable < ActiveRecord::Migration[4.2]
  def change
    create_table :inspirations do |t|
      t.string :type
      t.text :body
      t.timestamps
    end
  end
end
