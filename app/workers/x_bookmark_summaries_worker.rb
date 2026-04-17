class XBookmarkSummariesWorker
  include Sidekiq::Worker

  sidekiq_options retry: false, queue: :default

  def perform
    # We only run this monthly (on the last day of the month)
    return unless DateTime.now.to_date.end_of_month == DateTime.now.to_date

    User.where.not(x_refresh_token: nil).each do |user|
      XBookmark.sync_for_user!(user, max_results: 30)
      UserMailer.x_bookmarks_summary(user, DateTime.now.beginning_of_month).deliver_now
    end
  end
end
