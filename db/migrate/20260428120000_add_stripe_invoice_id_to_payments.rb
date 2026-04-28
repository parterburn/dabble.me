class AddStripeInvoiceIdToPayments < ActiveRecord::Migration[6.1]
  def change
    add_column :payments, :stripe_invoice_id, :string
    add_index :payments, :stripe_invoice_id, unique: true, where: 'stripe_invoice_id IS NOT NULL'
  end
end
