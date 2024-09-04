class Admin::StatsController < ApplicationController
  def index
    @dashboard = AdminStats.new
    @users = User.all
    @entries = Entry.all

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
    @pro_users = @users.pro_only
    @free_users = @users.free_only
    @monthly_users = @users.monthly
    @yearly_users = @users.yearly
    @forever_users = @users.forever
    @payhere_users = @users.payhere_only
    @gumroad_users = @users.gumroad_only
    @paypal_users = @users.paypal_only
    @referral_users = @users.referrals

    # Email statistics
    @emails_sent_total = @users.sum(:emails_sent)
    @emails_received_total = @users.sum(:emails_received)

    # Paginate large datasets
    @upgrades = @dashboard.upgraded_users_since(90.days.ago).page(params[:upgrades_page]).per(20)
    @bounces = @dashboard.bounced_users_since(90.days.ago).page(params[:bounces_page]).per(20)
    @free_users_recent = @dashboard.free_users_created_since(90.days.ago).order(:created_at).page(params[:free_users_page]).per(20)
  end
end
