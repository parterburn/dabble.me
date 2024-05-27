class EntryJob < ActiveJob::Base
  queue_as :default

  retry_on RestClient::Unauthorized, wait: 5.minutes, attempts: 3

  def perform(user_id, random_inspiration_id, sent_in_hour)
    user = User.find(user_id)
    random_inspiration = Inspiration.find(random_inspiration_id)
    EntryMailer.send_entry(user, random_inspiration).deliver_now
  rescue StandardError => e
    Sentry.set_user(id: user.id, email: user.email)
    Sentry.set_tags(plan: user.plan)
    Sentry.capture_exception(e, extra: { sent_in_hour: sent_in_hour })
    raise
  end
end
