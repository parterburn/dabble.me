class EntryWorker
  include Sidekiq::Worker
  sidekiq_options :retry => 1, :queue => :entry, :backtrace => true

  def perform(user_id)
    EntryMailer.send_entry(User.find(user_id)).deliver_later
  end
end