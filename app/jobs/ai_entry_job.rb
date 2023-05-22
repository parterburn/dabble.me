class AiEntryJob < ActiveJob::Base
  queue_as :default

  def perform(user, entry)
    return nil if ::Rails.env.test?

    EntryMailer.respond_as_ai(user, entry).deliver_now
  end
end
