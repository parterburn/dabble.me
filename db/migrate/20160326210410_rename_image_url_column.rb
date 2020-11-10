class RenameImageUrlColumn < ActiveRecord::Migration[4.2]
  def change
    rename_column :entries, :image_url, :filepicker_url
  end
end
