class AddImageToEntry < ActiveRecord::Migration
  def change
    add_column :entries, :image, :string
  end
end
