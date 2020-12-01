class CreateReviews < ActiveRecord::Migration[6.0]
  def change
    create_table :reviews do |t|
      t.references :user, index: true, foreign_key: true
      t.references :entry, index: true, foreign_key: true
      t.text :review_body
      t.string :status, default: 'new'
      t.timestamps null: false
    end
  end
end
