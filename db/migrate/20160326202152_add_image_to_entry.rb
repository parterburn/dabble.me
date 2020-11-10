class AddImageToEntry < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :image, :string
  end
end
