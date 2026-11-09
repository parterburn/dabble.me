# Photos live in S3 under uploads/<key>/<date>/. Until now that key was the
# user's posting key (user_key), so the posting key could never change without
# breaking every stored photo. image_key holds the photo folder from here on and
# never changes; existing users keep the folder they already have.
class AddImageKeyToUsers < ActiveRecord::Migration[6.1]
  def up
    add_column :users, :image_key, :string
    execute "UPDATE users SET image_key = user_key WHERE image_key IS NULL"
    add_index :users, :image_key, unique: true
  end

  def down
    remove_index :users, :image_key
    remove_column :users, :image_key
  end
end
