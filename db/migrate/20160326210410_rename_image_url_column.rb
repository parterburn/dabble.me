class RenameImageUrlColumn < ActiveRecord::Migration
  def change
    rename_column :entries, :image_url, :filepicker_url
  end
end
