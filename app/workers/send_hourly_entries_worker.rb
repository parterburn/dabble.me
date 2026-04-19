class SendHourlyEntriesWorker
  include Sidekiq::Worker
  include Sentry::Cron::MonitorCheckIns

  sidekiq_options retry: false, queue: :default

  # Sentry cron monitoring — this is the most important scheduled job, and our
  # Sentry plan only allows one cron monitor, so we don't enable the
  # `:sidekiq_cron` patch globally (that would register a monitor for every
  # job in config/sidekiq_cron_schedule.yml). The mixin below registers a
  # single monitor and emits in_progress/ok/error check-ins automatically.
  #
  # IMPORTANT: the crontab here must stay in sync with the entry in
  # config/sidekiq_cron_schedule.yml — if you change the schedule there,
  # update this line too or Sentry will report missed/late runs.
  sentry_monitor_check_ins(
    slug: "send_hourly_entries",
    monitor_config: Sentry::Cron::MonitorConfig.from_crontab("0 * * * *")
  )

  def perform
    random_inspiration = Inspiration.random
    sent_in_hour = 0
    failed_in_hour = 0

    User.subscribed_to_emails.not_just_signed_up.find_each(batch_size: 100) do |user|
      Sentry.with_scope do |scope|
        scope.set_user(id: user.id, email: user.email)
        scope.set_tags(plan: user.plan, worker: "send_hourly_entries")

        begin
          next unless should_send?(user)

          if disable_free_user?(user)
            user.update_columns(frequency: [], previous_frequency: user.frequency)
          elsif eligible_to_send?(user)
            EntryMailer.send_entry(user, random_inspiration).deliver_now
            sent_in_hour += 1
          end
        rescue StandardError => e
          failed_in_hour += 1
          Sentry.capture_exception(e, extra: { sent_in_hour: sent_in_hour, failed_in_hour: failed_in_hour })
          # swallow the error so one bad user doesn't stop the rest of the hourly run
        end
      end
    end

    Rails.logger.info("SendHourlyEntriesWorker finished: sent=#{sent_in_hour} failed=#{failed_in_hour}")
  end

  private

  def should_send?(user)
    return false if user.send_time.blank? || user.send_timezone.blank?

    now_local = Time.now.in_time_zone(user.send_timezone)

    send_this_day = user.frequency && user.frequency.include?(now_local.strftime('%a'))
    send_this_hour = now_local.hour == user.send_time.hour

    # retry if previous 2 hours in scheduler failed to send and last email was sent over 20 hours ago
    retry_failed_scheduler = user.last_sent_at.present? &&
                             user.last_sent_at.before?(20.hours.ago) &&
                             (now_local.hour - user.send_time.hour).between?(0, 2)

    return false unless send_this_day && (send_this_hour || retry_failed_scheduler)
    # prevent sending multiple emails to same user in same day
    return false if user.last_sent_at.present? && user.last_sent_at.after?(12.hours.ago)

    true
  end

  # Stop emailing free users who have 6+ emails sent and no entries (to reduce spam reports).
  def disable_free_user?(user)
    user.is_free? && user.emails_sent > 6 && user.entries.count == 0 && ENV['FREE_WEEK'] != 'true'
  end

  # Pro users get emails every eligible hour; free users only on even-numbered ISO weeks (or FREE_WEEK).
  def eligible_to_send?(user)
    user.is_pro? ||
      (user.is_free? && Time.now.strftime("%U").to_i.even?) ||
      ENV['FREE_WEEK'] == 'true'
  end
end
