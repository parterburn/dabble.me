# Deletes emailed sign-in and confirmation codes (EmailCode) once they're past any use: expired,
# and older than the day EmailCode counts wrong guesses over.
class EmailCodeCleanupWorker
  include Sidekiq::Job

  sidekiq_options retry: false, queue: :default

  def perform
    EmailCode.cleanup!
  end
end
