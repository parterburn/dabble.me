class UserDowngradeExpiredWorker
  include Sidekiq::Worker

  sidekiq_options retry: false, queue: :default

  def perform
    downgrade_yearly
    downgrade_monthly
  end

  private

  def downgrade_yearly
    User.pro_only.yearly.not_forever.joins(:payments)
        .where("payments.amount > ?", 10.00)
        .having("MAX(payments.date) < ?", 375.days.ago)
        .group("users.id")
        .each { |user| downgrade(user) }
  end

  def downgrade_monthly
    User.pro_only.monthly.not_forever.joins(:payments)
        .where("payments.amount > ?", 1.00)
        .having("MAX(payments.date) < ?", 40.days.ago)
        .group("users.id")
        .each { |user| downgrade(user, skip_ids: [16094, 10763]) }
  end

  def downgrade(user, skip_ids: [])
    if user.has_active_stripe_subscription?
      unless user.id.in?(skip_ids)
        Sentry.set_user(id: user.id, email: user.email)
        Sentry.set_tags(plan: user.plan)
        Sentry.capture_message("Downgrade attempt for active Stripe subscription user", level: :error)
      end
      return
    end

    user.update(plan: "Free")

    begin
      UserMailer.downgraded(user).deliver_now
    rescue StandardError => e
      Sentry.set_user(id: user.id, email: user.email)
      Sentry.set_tags(plan: user.plan)
      Sentry.capture_exception(e, extra: { email_type: "downgrade_expired" })
    end
  end
end
