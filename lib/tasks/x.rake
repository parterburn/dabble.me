# Personal use: X bookmarks. See lib/tasks/X_BOOKMARKS_SETUP.md for initial setup.
namespace :x do
  desc 'One-time: save X tokens to your user record from the manual OAuth flow'
  task :save_tokens, [:email, :access_token, :refresh_token] => :environment do |_t, args|
    user = User.find_by!(email: args[:email])
    user.update!(x_access_token: args[:access_token], x_refresh_token: args[:refresh_token])

    client = XApiClient.new(access_token: args[:access_token])
    if (profile = client.current_user)
      user.update!(x_uid: profile.dig('data', 'id'), x_username: profile.dig('data', 'username'))
      puts "Saved tokens for @#{user.x_username} (#{user.x_uid})"
    else
      puts "Tokens saved but could not fetch X profile — token may already be expired."
    end
  end

  desc 'Sync X bookmarks to DB and send monthly summaries'
  # rake x:bookmark_summaries
  task :bookmark_summaries => :environment do |_t, args|
    if DateTime.now.to_date.end_of_month == DateTime.now.to_date
      # We only run this monthly

      User.where.not(x_refresh_token: nil).each do |user|
        XBookmark.sync_for_user!(user, max_results: 30)
        UserMailer.x_bookmarks_summary(user, since: DateTime.now.beginning_of_month).deliver_now
      end
    end
  end
end
