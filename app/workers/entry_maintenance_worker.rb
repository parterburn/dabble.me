class EntryMaintenanceWorker
  include Sidekiq::Worker

  sidekiq_options retry: false, queue: :default

  def perform
    # Clean up empty entries
    Entry.where("(image IS null OR image = '') AND (body IS null OR body = '')").each(&:destroy)

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
