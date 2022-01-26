class StorePreviousFrequency < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :previous_frequency, :text, default: [], array: true
  end
end
