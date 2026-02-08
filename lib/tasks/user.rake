namespace :user do

  # rake user:downgrade_expired
  task :downgrade_expired => :environment do
    User.pro_only.yearly.not_forever.joins(:payments).where("payments.amount > ?", 10.00).having("MAX(payments.date) < ?", 375.days.ago).group("users.id").each do |user|
      if user.has_active_stripe_subscription?
        Sentry.set_user(id: user.id, email: user.email)
        Sentry.set_tags(plan: user.plan)
        Sentry.capture_message("Downgrade attempt for active Stripe subscription user", level: :error)
        next
      else
        user.update(plan: "Free")
      end

      begin
        UserMailer.downgraded(user).deliver_now
      rescue StandardError => e
        Sentry.set_user(id: user.id, email: user.email)
        Sentry.set_tags(plan: user.plan)
        Sentry.capture_exception(e, extra: { email_type: "downgrade_expired" })
      end
    end

    User.pro_only.monthly.not_forever.joins(:payments).where("payments.amount > ?", 1.00).having("MAX(payments.date) < ?", 40.days.ago).group("users.id").each do |user|
      if user.has_active_stripe_subscription?
        if !user.id.in?([16094, 10763]) # skip known issues
          Sentry.set_user(id: user.id, email: user.email)
          Sentry.set_tags(plan: user.plan)
          Sentry.capture_message("Downgrade attempt for active Stripe subscription user", level: :error)
        end
        next
      else
        user.update(plan: "Free")
      end

      begin
        UserMailer.downgraded(user).deliver_now
      rescue StandardError => e
        Sentry.set_user(id: user.id, email: user.email)
        Sentry.set_tags(plan: user.plan)
        Sentry.capture_exception(e, extra: { email_type: "downgrade_expired" })
      end
    end
  end

end
