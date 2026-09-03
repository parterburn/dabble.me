class FounderMailer < ActionMailer::Base
  helper.extend(ApplicationHelper)
  helper ApplicationHelper

  default from: "Dabble Me Stats <hello@#{ENV['MAIN_DOMAIN']}>"

  def weekly_digest(recipients, dashboard)
    @dashboard = dashboard
    @stats_url = admin_stats_url_for_mail
    mail(
      to: recipients,
      subject: weekly_subject(dashboard)
    )
  end

  private

  def weekly_subject(dashboard)
    arr = dashboard.format_cents(dashboard.revenue.arr_cents)
    delta = dashboard.arr_delta_week_cents
    delta_text = if delta.nil?
      "no prior week"
    else
      dashboard.format_delta(delta)
    end

    gained = dashboard.latest_snapshot&.new_subscriber_count
    lost = dashboard.latest_snapshot&.canceled_subscriber_count
    movement = if gained.nil? || lost.nil?
      nil
    else
      "#{gained} gained, #{lost} lost"
    end

    ["Dabble Me weekly: #{arr} ARR (#{delta_text})", movement].compact.join(" · ")
  end

  def admin_stats_url_for_mail
    "#{ApplicationHelper.site_public_base_url}/admin/stats"
  end
end
