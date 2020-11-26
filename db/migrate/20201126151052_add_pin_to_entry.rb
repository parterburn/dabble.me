class AddPinToEntry < ActiveRecord::Migration[6.0]
  def change
    add_column :entries, :pinned, :boolean, default: false
  end
end
