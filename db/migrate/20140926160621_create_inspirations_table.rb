class CreateInspirationsTable < ActiveRecord::Migration
  def change
    create_table :inspirations do |t|
      t.string :type
      t.text :body
      t.timestamps
    end
  end
end
