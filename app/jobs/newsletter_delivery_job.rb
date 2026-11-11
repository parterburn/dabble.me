# Sends one person their letter of a newsletter, at most once.
#
# The delivery row is written before the email goes out, and the unique index
# on it turns a second attempt into a no-op. If sending fails the row is
# removed so a retry can try again. A crash between the two loses that one
# email rather than risking a duplicate.
class NewsletterDeliveryJob < ActiveJob::Base
  queue_as :default

  def perform(user_id, newsletter_key)
    newsletter = Newsletter.find(newsletter_key)
    user = User.find_by(id: user_id)
    # They may have unsubscribed, downgraded or deleted since it was queued.
    return unless user && newsletter.recipient?(user)

    variant = newsletter.variant_for(user)
    delivery = NewsletterDelivery.create!(user: user, newsletter: newsletter.key, variant: variant, created_at: Time.current)

    begin
      NewsletterMailer.letter(user, newsletter.key, variant).deliver_now
    rescue StandardError
      delivery.destroy
      raise
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
