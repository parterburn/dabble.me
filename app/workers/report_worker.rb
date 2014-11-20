class ReportWorker
  include Sidekiq::Worker
  sidekiq_options :retry => 1, :queue => :entry, :backtrace => true

  def perform(total_sent_before, sent_this_session, sent_time)
    EntryMailer.sent_report(total_sent_before, sent_this_session, sent_time)
  end
end