require 'stripe'

namespace :user do

  # rake user:downgrade_expired
  task :downgrade_expired => :environment do
    Stripe.api_key = ENV['STRIPE_API_KEY']

    User.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 368.days.ago).group("users.id").each do |user|
      if user.payments.last.date.before?(368.days.ago) # double check
        begin
          if user.stripe_id.present?
            charges = Stripe::Charge.list({ customer: user.stripe_id })
            if charges && charges.data.any?
              latest_charge = charges.data.first
              latest_charge_date = Time.at(latest_charge.created)
              latest_charge_amount = latest_charge.amount.to_f / 100
              if latest_charge_date.after?(368.days.ago) && latest_charge_amount > 3.0
                Sentry.set_user(id: user.id, email: user.email)
                Sentry.set_tags(plan: user.plan)
                Sentry.capture_exception("Downgrade attempt for paid user", extra: { latest_charge: latest_charge })
                next # triple check
              end
            end
          end
          user.update(plan: "Free")
          UserMailer.downgraded(user).deliver_now
        rescue StandardError => e
          Sentry.set_user(id: user.id, email: user.email)
          Sentry.set_tags(plan: user.plan)
          Sentry.capture_exception(e, extra: { email_type: "downgrade_expired" })
        end
      end
    end

    User.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 33.days.ago).group("users.id").each do |user|
      if user.payments.last.date < 33.days.ago # double check
        begin
          if user.stripe_id.present?
            charges = Stripe::Charge.list({ customer: user.stripe_id })
            if charges && charges.data.any?
              latest_charge = charges.data.first
              latest_charge_date = Time.at(latest_charge.created)
              latest_charge_amount = latest_charge.amount.to_f / 100
              if latest_charge_date.after?(33.days.ago) && latest_charge_amount > 2.0
                Sentry.set_user(id: user.id, email: user.email)
                Sentry.set_tags(plan: user.plan)
                Sentry.capture_exception("Downgrade attempt for paid user", extra: { latest_charge: latest_charge })
                next # triple check
              end
            end
          end

          user.update(plan: "Free")
          UserMailer.downgraded(user).deliver_now
        rescue StandardError => e
          Sentry.set_user(id: user.id, email: user.email)
          Sentry.set_tags(plan: user.plan)
          Sentry.capture_exception(e, extra: { email_type: "downgrade_expired" })
        end
      end
    end
  end

  # task :update_stripe_id => :environment do
  #   # Runs daily
  #   users_to_update = User.where(stripe_id: [nil, ""]).where.not(payhere_id: [nil, ""]).where.not(plan: "Free")
  #   if users_to_update.any?
  #     Stripe.api_key = ENV['STRIPE_API_KEY']
  #     stripe_subs = Stripe::Subscription.list(limit: 100)
  #     all_stripe_subs = []
  #     stripe_subs.auto_paging_each do |stripe_sub|
  #       all_stripe_subs << stripe_sub
  #     end

  #     users_to_update.each do |user|
  #       stripe_sub = all_stripe_subs.select { |ss| ss.metadata["dabble_id"] == user.id.to_s }&.first
  #       stripe_sub ||= all_stripe_subs.select { |ss| ss.metadata["customer_email"] == user.email }&.first
  #       user.update_column(stripe_id: stripe_sub&.customer) if stripe_sub.present?
  #     end
  #   end
  # end

  # task :downgrade_gumroad_expired => :environment do
  #   User.gumroad_only.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 368.days.ago).group("users.id").each do |user|
  #     user.update(plan: "Free")
  #     begin
  #       UserMailer.downgraded(user).deliver_now
  #     rescue StandardError => e
  #       Sentry.set_user(id: user.id, email: user.email)
  #       Sentry.set_tags(plan: user.plan)
  #       Sentry.capture_exception(e, extra: { email_type: "downgrade_gumroad_expired" })
  #     end
  #   end

  #   User.gumroad_only.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 33.days.ago).group("users.id").each do |user|
  #     user.update(plan: "Free")
  #     begin
  #       UserMailer.downgraded(user).deliver_now
  #     rescue StandardError => e
  #       Sentry.set_user(id: user.id, email: user.email)
  #       Sentry.set_tags(plan: user.plan)
  #       Sentry.capture_exception(e, extra: { email_type: "downgrade_gumroad_expired" })
  #     end
  #   end
  # end

  # task :downgrade_payhere_expired => :environment do
  #   User.payhere_only.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 368.days.ago).group("users.id").each do |user|
  #     user.update(plan: "Free")
  #     begin
  #       UserMailer.downgraded(user).deliver_now
  #     rescue StandardError => e
  #       Sentry.set_user(id: user.id, email: user.email)
  #       Sentry.set_tags(plan: user.plan)
  #       Sentry.capture_exception(e, extra: { email_type: "downgrade_payhere_expired" })
  #     end
  #   end

  #   User.payhere_only.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 33.days.ago).group("users.id").each do |user|
  #     user.update(plan: "Free")
  #     begin
  #       UserMailer.downgraded(user).deliver_now
  #     rescue StandardError => e
  #       Sentry.set_user(id: user.id, email: user.email)
  #       Sentry.set_tags(plan: user.plan)
  #       Sentry.capture_exception(e, extra: { email_type: "downgrade_payhere_expired" })
  #     end
  #   end
  # end

  # task :downgrade_paypal_expired => :environment do
  #   User.paypal_only.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 368.days.ago).group("users.id").each do |user|
  #     user.update(plan: "Free")
  #     begin
  #       UserMailer.downgraded(user).deliver_now
  #     rescue StandardError => e
  #       Sentry.set_user(id: user.id, email: user.email)
  #       Sentry.set_tags(plan: user.plan)
  #       Sentry.capture_exception(e, extra: { email_type: "downgrade_paypal_expired" })
  #     end
  #   end

  #   User.paypal_only.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 33.days.ago).group("users.id").each do |user|
  #     user.update(plan: "Free")
  #     begin
  #       UserMailer.downgraded(user).deliver_now
  #     rescue StandardError => e
  #       Sentry.set_user(id: user.id, email: user.email)
  #       Sentry.set_tags(plan: user.plan)
  #       Sentry.capture_exception(e, extra: { email_type: "downgrade_paypal_expired" })
  #     end
  #   end
  # end

  # task :handle_free_week => :environment do
  #   if ENV['FREE_WEEK'].present?
  #       User.free_only.select { |u| u.frequency.present? }.each do |user|
  #         if ENV['FREE_WEEK'] == 'true'
  #           user.update_columns(frequency: ['Sun', 'Wed', 'Fri'], previous_frequency: user.frequency)
  #         elsif ENV['FREE_WEEK'] == 'false'
  #           user.update_columns(frequency: ['Sun'], previous_frequency: user.frequency)
  #         end
  #       end
  #   end
  # end

end
