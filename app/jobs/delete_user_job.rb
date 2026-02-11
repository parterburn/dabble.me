class DeleteUserJob < ActiveJob::Base
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user # Already deleted
    return unless user.deleted_at.present? # Deletion was cancelled

    # Capture user info before deletion for logging
    user_email = user.email
    user_plan = user.plan
    entries_count = user.entries.count
    payhere_id = user.payhere_id
    stripe_id = user.stripe_id

    # Cancel Stripe subscription (should already be cancelled, but ensures cleanup)
    if stripe_id.present?
      begin
        customer = Stripe::Customer.retrieve(stripe_id)
        customer.subscriptions.each(&:cancel)
      rescue Stripe::InvalidRequestError
        # Already cancelled or customer doesn't exist - that's fine
      end
    end

    # Destroy entries in batches to avoid memory issues and trigger CarrierWave cleanup
    Entry.where(user_id: user_id).find_each(batch_size: 100, &:destroy)

    # Destroy remaining associations and the user
    user.original_hashtags.delete_all
    user.webauthn_credentials.delete_all
    user.delete

    # Log the deletion
    if user_plan.present? && user_plan.match(/pro/i)
      Sentry.capture_message('Pro User Deleted', level: :info, extra: {
        email: user_email,
        plan: user_plan,
        entries: entries_count,
        user_id: user_id,
        payhere_id: payhere_id,
        stripe_id: stripe_id,
        deleted_at: user.deleted_at
      })
    end
  end
end
