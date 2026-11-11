class CreateAiUsages < ActiveRecord::Migration[8.1]
  # One row per AI reflection: who asked, which model answered, the tokens
  # it used and what that cost. No entry text.
  def change
    create_table :ai_usages do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :model, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      # US dollars, priced from RubyLLM's model registry. Null when the
      # registry has no price for the model.
      t.decimal :cost_usd, precision: 12, scale: 6
      t.datetime :created_at, null: false
    end
    add_index :ai_usages, [:user_id, :created_at]
  end
end
