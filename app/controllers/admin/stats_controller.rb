class Admin::StatsController < ApplicationController
  def index
    @stats = Rails.cache.fetch("admin_stats", expires_in: 1.hour) do
      AdminStatsService.new.generate_stats
    end

    @upgrades = User.pro.order(created_at: :desc).page(params[:upgrades_page]).per(20)
    @bounces = User.with_bounced_emails.order(updated_at: :desc).page(params[:bounces_page]).per(20)
    @free_users_recent = User.free.where('created_at > ?', 90.days.ago).order(created_at: :desc).page(params[:free_users_page]).per(20)
  end
end
