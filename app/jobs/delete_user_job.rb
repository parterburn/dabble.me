class DeleteUserJob < ActiveJob::Base
  queue_as :default

  # +requested_at+ is the deleted_at (epoch seconds) the deletion was scheduled with. A
  # deletion cancelled by signing back in and asked for again gets a new deleted_at and a job
  # of its own, so this older job must not cut the new hour short. Jobs queued before it was
  # passed have none and keep the old check.
  def perform(user_id, requested_at = nil)
    user = User.find_by(id: user_id)
    return unless user # Already deleted
    return unless user.deleted_at.present? # Deletion was cancelled
    return if requested_at && user.deleted_at.to_i != requested_at # Cancelled, then asked for again
    # Admins keep their passkeys (AdminAccounts), so the app never deletes one. A deletion
    # queued before they were made admin stops here. The console deletes an admin with
    # AdminAccounts.allow_passkey_removal { user.destroy! }.
    return refuse_admin(user) if AdminAccounts.protected?(user)

    # Capture user info before deletion for logging
    user_email = user.email
    user_plan = user.plan
    entries_count = user.entries.count
    payhere_id = user.payhere_id
    stripe_id = user.stripe_id

    cancel_stripe_subscriptions(stripe_id)

    # Destroy entries in batches to avoid memory issues and trigger CarrierWave cleanup
    Entry.where(user_id: user_id).find_each(batch_size: 100, &:destroy)

    # Exports' ZIPs too, now: `user.delete` below skips callbacks, and the database's cascade
    # would leave the files in storage until the bucket's lifecycle rule.
    user.exports.find_each(&:destroy)

    # Destroy remaining associations (including Doorkeeper OAuth rows) and the user atomically
    refused = false
    ActiveRecord::Base.transaction do
      # Checked again under a lock: the entries above can take a while, and delete_all below
      # skips WebauthnCredential's guard. Leaving the block (not rolling back) keeps the
      # cleared deleted_at.
      user.lock!
      if AdminAccounts.protected?(user)
        refused = true
        refuse_admin(user)
        next
      end

      Doorkeeper::AccessGrant.where(resource_owner_id: user_id).delete_all
      Doorkeeper::AccessToken.where(resource_owner_id: user_id).delete_all
      user.original_hashtags.delete_all
      user.webauthn_credentials.delete_all
      user.delete
    end
    return if refused

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

  private

  def refuse_admin(user)
    user.update_column(:deleted_at, nil)
    Sentry.capture_message('Admin account deletion refused', level: :warning, extra: { user_id: user.id })
    nil
  end

  def cancel_stripe_subscriptions(stripe_id)
    return if stripe_id.blank?

    Stripe::Subscription.list(customer: stripe_id).auto_paging_each(&:cancel)
  rescue Stripe::InvalidRequestError => e
    Sentry.capture_exception(e, extra: { stripe_id: stripe_id })
  end
end
