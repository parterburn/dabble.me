class CreateFrequencyField < ActiveRecord::Migration[6.0]  
  def up
    add_column :users, :frequency_upd, :text, array: true, default: ["Sun"]
  end
end