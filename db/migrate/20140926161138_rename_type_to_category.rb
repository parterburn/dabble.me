class RenameTypeToCategory < ActiveRecord::Migration
  def change
    change_table :inspirations do |t|
      t.rename :type, :category
    end
  end
end
