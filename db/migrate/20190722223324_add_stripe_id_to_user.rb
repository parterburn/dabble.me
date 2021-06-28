class AddStripeIdToUser < ActiveRecord::Migration[4.2]
  def change
    add_column :users, :stripe_id, :string
  end
end
