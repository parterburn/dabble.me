class AddLastSentAtToUsers < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :last_sent_at, :datetime

    User.all.each do |user|
      next unless user.emails_sent.positive?

      user.update(last_sent_at: user.entries.first.date.presence || 3.hours.ago)
    end
  end
end
