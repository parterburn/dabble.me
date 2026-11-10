class EntryMaintenanceWorker
  include Sidekiq::Job

  sidekiq_options retry: false, queue: :default

  def perform
    # Fill in word counts for any entry saved without one (rows written by
    # code that predates the column, or with callbacks skipped).
    Entry.unscoped.where(word_count: nil).find_each do |entry|
      entry.update_column(:word_count, Entry.count_words(entry.body))
    end

    # Clean up empty entries
    # word_count = 0 narrows the candidates without reading entry text in SQL;
    # the body check in Ruby keeps the rule exactly "no image and no body".
    Entry.unscoped.where("(image IS null OR image = '') AND word_count = 0").find_each do |entry|
      entry.destroy if entry.body.nil? || entry.body == ''
    end

    # Turn off emails for users with low entries and no activity for 2 years
    users_with_no_activity = User.joins(:entries)
                                 .group('users.id')
                                 .having('COUNT(entries.id) < 5')
                                 .having('MAX(entries.created_at) < ?', 2.years.ago)
                                 .where.not(frequency: [])

    users_with_no_activity.each do |user|
      user.previous_frequency = user.frequency
      user.frequency = []
      user.save
    end
  end
end
