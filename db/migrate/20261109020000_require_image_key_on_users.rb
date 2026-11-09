# Makes image_key required before posting addresses can be reset. It only
# fills in missing photo-folder keys; it never changes anyone's user_key
# (posting address).
class RequireImageKeyOnUsers < ActiveRecord::Migration[6.1]
  def up
    # Accounts created by old code while the image_key migration deployed.
    # Their photos were stored under user_key, so copy it exactly.
    execute "UPDATE users SET image_key = user_key WHERE image_key IS NULL"
    # An account with no user_key has no photo folder to keep, so any unused
    # value works. md5 hex fits the usual "u" + 18 [0-9a-z] format.
    execute <<~SQL
      UPDATE users SET image_key = 'u' || substr(md5(random()::text || id::text), 1, 18)
      WHERE image_key IS NULL
    SQL
    change_column_null :users, :image_key, false
  end

  def down
    change_column_null :users, :image_key, true
  end
end
