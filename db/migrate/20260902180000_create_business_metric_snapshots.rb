class CreateBusinessMetricSnapshots < ActiveRecord::Migration[6.1]
  def change
    create_table :business_metric_snapshots do |t|
      t.date :captured_on, null: false

      t.integer :mrr_cents, null: false, default: 0
      t.integer :arr_cents, null: false, default: 0
      t.integer :gross_new_mrr_cents, null: false, default: 0
      t.integer :churned_mrr_cents, null: false, default: 0
      t.integer :cash_collected_cents, null: false, default: 0

      t.integer :recurring_subscriber_count, null: false, default: 0
      t.integer :new_subscriber_count, null: false, default: 0
      t.integer :canceled_subscriber_count, null: false, default: 0
      t.integer :lifetime_subscriber_count, null: false, default: 0

      t.integer :active_pro_7d, null: false, default: 0
      t.integer :active_pro_30d, null: false, default: 0
      t.integer :active_pro_90d, null: false, default: 0
      t.integer :active_pro_365d, null: false, default: 0
      t.integer :active_free_7d, null: false, default: 0
      t.integer :active_free_30d, null: false, default: 0
      t.integer :active_free_90d, null: false, default: 0
      t.integer :active_free_365d, null: false, default: 0
      t.integer :paid_inactive_30d, null: false, default: 0
      t.integer :paid_inactive_90d, null: false, default: 0

      t.integer :signups_30d, null: false, default: 0
      t.integer :first_entry_72h_30d, null: false, default: 0
      t.integer :three_entry_14d_30d, null: false, default: 0
      t.decimal :first_entry_activation_rate, precision: 6, scale: 4
      t.decimal :three_entry_activation_rate, precision: 6, scale: 4

      t.integer :email_sent_count, null: false, default: 0
      t.integer :email_failed_count, null: false, default: 0
      t.integer :email_replies_count, null: false, default: 0
      t.decimal :email_delivery_rate, precision: 6, scale: 4
      t.decimal :email_reply_rate, precision: 6, scale: 4

      t.jsonb :plan_breakdown, null: false, default: {}
      t.jsonb :acquisition_breakdown, null: false, default: {}
      t.jsonb :subscriber_map, null: false, default: {}

      t.timestamps
    end

    add_index :business_metric_snapshots, :captured_on, unique: true
  end
end
