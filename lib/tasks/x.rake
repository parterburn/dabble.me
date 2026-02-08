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

  desc 'Sync X bookmarks to DB (skips duplicates, paginates through all)'
  # rake x:sync_bookmarks[admin@dabble.ex]
  task :sync_bookmarks, [:email] => :environment do |_t, args|
    abort "Not Friday! Syncing X bookmarks is only available on Fridays." unless Time.current.friday?

    user = User.find_by!(email: args[:email])
    abort "No X tokens on record. Run rake x:save_tokens first." unless user.x_connected?

    new_count = XBookmark.sync_for_user!(user, max_results: 15)
    puts "#{new_count} new bookmarks saved (#{user.x_bookmarks.count} total)"

    UserMailer.x_bookmarks_summary(user).deliver_now
  end
end
