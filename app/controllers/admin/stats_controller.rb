class Admin::StatsController < ApplicationController
  def index
    @dashboard = AdminStats.new
    @users = User.all

    # Preload data for charts
    @users_by_week = @dashboard.users_by_week_since(90.days.ago)
    @pro_users_by_week = @dashboard.pro_users_by_week_since(90.days.ago)
    @entries_by_week = @dashboard.entries_by_week_since(90.days.ago)
    @emails_sent_by_month = @dashboard.emails_sent_by_month_since(90.days.ago)
    @payments_by_month = @dashboard.payments_by_month(1.year.ago)

    # Use counter cache for frequently accessed counts
    @all_count = Entry.count
    @photos_count = Entry.only_images.count
    @ai_entries_count = Entry.with_ai_responses.count

    # User statistics
    @total_users = @users.count
    @pro_users = @users.pro_only.count
    @monthly_users = @users.monthly.count
    @yearly_users = @users.yearly.count
    @forever_users = @users.forever.count
    @payhere_users = @users.payhere_only.count
    @gumroad_users = @users.gumroad_only.count
    @paypal_users = @users.paypal_only.count
    @referral_users = @users.referrals

    # Email statistics
    @emails_sent_total = @users.sum(:emails_sent)
    @emails_received_total = @users.sum(:emails_received)

    # Paginate large datasets
    @upgrades = @dashboard.upgraded_users_since(90.days.ago).page(params[:upgrades_page]).per(20)
    @bounces = @dashboard.bounced_users_since(90.days.ago).page(params[:bounces_page]).per(20)
  end
end
