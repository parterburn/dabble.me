# Personal use: X bookmarks. See lib/tasks/X_BOOKMARKS_SETUP.md for initial setup.
namespace :x do
  desc 'One-time: save X tokens to your user record from the manual OAuth flow'
  # rake x:save_tokens[you@email.com,ACCESS_TOKEN,REFRESH_TOKEN]
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

  desc 'Fetch X bookmarks for your user'
  # rake x:bookmarks[you@email.com]
  task :bookmarks, [:email] => :environment do |_t, args|
    user = User.find_by!(email: args[:email])
    abort "No X tokens on record. Run rake x:save_tokens first." unless user.x_connected?

    client = XApiClient.new(user: user)
    result = client.bookmarks
    if result['data']
      result['data'].each { |t| puts "#{t['created_at']} — #{t['text']}\n---" }
      puts "#{result.dig('meta', 'result_count')} bookmarks"
    else
      puts "Error: #{result.dig('errors', 0, 'message')}"
    end
  end
end
