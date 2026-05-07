class DropXBookmarksTable < ActiveRecord::Migration[6.1]
  def up
    drop_table :x_bookmarks
  end

  def down
    create_table :x_bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :tweet_id, null: false
      t.string :author_id
      t.string :author_username
      t.string :author_name
      t.text :text
      t.datetime :tweeted_at
      t.string :url
      t.jsonb :entities, default: {}
      t.jsonb :public_metrics, default: {}
      t.timestamps
    end

    add_index :x_bookmarks, [:user_id, :tweet_id], unique: true
  end
end
