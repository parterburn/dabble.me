# The one email an admin can send to everyone with a journal (ServiceNotice),
# and who has been sent each one.
class CreateServiceNotices < ActiveRecord::Migration[8.1]
  def change
    create_table :service_notices do |t|
      # The admin's own words above the fixed text. Plain text, may be empty.
      t.text :message
      # The admin who sent it. Kept as a bare id so the record outlives the account.
      t.bigint :sent_by_id
      t.integer :recipients_count, null: false, default: 0
      # One notice a day, enforced here so two clicks can't send two.
      t.date :sent_on, null: false
      t.datetime :created_at, null: false
      t.index :sent_on, unique: true
    end

    create_table :service_notice_deliveries do |t|
      t.references :service_notice, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.datetime :created_at, null: false
      # When the person asked for no more notices, from the link in this one.
      t.datetime :stopped_at
      # One copy of a notice per person, however often a job is retried.
      t.index %i[service_notice_id user_id], unique: true, name: "index_service_notice_deliveries_on_notice_and_user"
      t.index :user_id
    end
  end
end
