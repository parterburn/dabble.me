class RenameTypeToCategory < ActiveRecord::Migration[4.2]
  def change
    change_table :inspirations do |t|
      t.rename :type, :category
    end
  end
end
