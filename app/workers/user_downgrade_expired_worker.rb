class UserDowngradeExpiredWorker
  include Sidekiq::Job

  sidekiq_options retry: false, queue: :default

  def perform
    downgrade_yearly
    downgrade_monthly
    downgrade_gifts
  end

  private

  # Only web payments count: App Store charges (apple_transaction_id) would otherwise keep a
  # cancelled web plan alive forever, and Apple's own state decides those (AppStore::Entitlement).
  def downgrade_yearly
    User.pro_only.yearly.not_forever.not_apple.joins(:payments)
        .where(payments: { apple_transaction_id: nil })
        .where("payments.amount > ?", 7.00)
        .having("MAX(payments.date) < ?", 375.days.ago)
        .group("users.id")
        .each { |user| downgrade(user) }
  end

  def downgrade_monthly
    User.pro_only.monthly.not_forever.not_apple.joins(:payments)
        .where(payments: { apple_transaction_id: nil })
        .where("payments.amount > ?", 1.00)
        .having("MAX(payments.date) < ?", 40.days.ago)
        .group("users.id")
        .each { |user| downgrade(user, skip_ids: [16094, 10763]) }
  end

  # A gifted year (Gift) has no payments; it ends at the redemption's expires_at.
  def downgrade_gifts
    User.gifted.pro_only.joins(:gift_redemption)
        .where("gift_redemptions.expires_at < ?", Time.current)
        .find_each { |user| downgrade(user, gift: true) }
  end

  def downgrade(user, gift: false, skip_ids: [])
    if user.has_active_stripe_subscription?
      unless user.id.in?(skip_ids)
        Sentry.set_user(id: user.id, email: user.email)
        Sentry.set_tags(plan: user.plan)
        Sentry.capture_message("Downgrade attempt for active Stripe subscription user", level: :error, extra: { email: user.email, plan: user.plan })
      end
      return
    end

    return unless user.update(plan: "Free")
    # An App Store subscription still paid for takes over (User#resume_apple_subscription).
    return unless user.reload.is_free?

    begin
      UserMailer.downgraded(user, gift: gift).deliver_now
    rescue StandardError => e
      Sentry.set_user(id: user.id, email: user.email)
      Sentry.set_tags(plan: user.plan)
      Sentry.capture_exception(e, extra: { email_type: "downgrade_expired" })
    end
  end
end
