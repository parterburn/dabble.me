class AddSentimentToEntry < ActiveRecord::Migration[6.1]
  def change
    add_column :entries, :sentiment, :jsonb, default: [], array:true
  end
end
