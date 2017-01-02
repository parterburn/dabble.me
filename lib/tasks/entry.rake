namespace :entry do

  # rake entry:send_entries_test
  task :send_entries_test => :environment do
    user = User.where(:email=>"admin@dabble.ex").first
    EntryMailer.send_entry(user).deliver_now
  end

  # rake "entry:stats[2016]"
  task :stats, [:year] => :environment do |_, year:|
    # Stats for 2015
    # 3,872 users created
    # 87,572 entries created
    # 5,017,056 total words
    # 150.4 avg words
    # 28,602,926 characters
    # 857.30 avg characters per post (6.1 tweets)
    # 171,919 were the word "I"

    # Stats for 2016
    # 31,832 entries craeted in 2016
    # 1,068 users created
    # Total characters: 676,779
  
    p "*"*100
    p "STATS FOR #{year}"
    p "*"*100

    extend ActionView::Helpers::NumberHelper    
    all_entries = Entry.where("date >= '#{year}-01-01'::DATE AND date <= '#{year}-12-31'::DATE")
    entries_bodies = []
    all_entries.each do |entry|
      entries_bodies << entry.body
    end
    entries_bodies = entries_bodies.join(" "); nil
    words_counter = WordsCounted.count(entries_bodies, exclude: ['p', 'br', 'div', 'img', 'span'])
    total_words = words_counter.token_count.to_f
    avg_words = total_words / all_entries.count
    total_chars = entries_bodies.length
    avg_chars = total_chars / all_entries.count
    avg_tweets_per_post = ((avg_chars).to_f / 140).ceil
    most_frequent = words_counter.token_frequency.first(10)
    p "Users created: #{number_with_delimiter(User.where("created_at >= '#{year}-01-01'::DATE AND created_at <= '#{year}-12-31'::DATE").count)}"
    p "Entries created in #{year}: #{number_with_delimiter(Entry.where("created_at >= '#{year}-01-01'::DATE AND created_at <= '#{year}-12-31'::DATE").count)}"
    p "Entries for #{year}: #{number_with_delimiter(all_entries.count)}"
    p "Total words: #{number_with_delimiter(total_words)}"
    p "Avg words per post: #{number_with_delimiter(avg_words)}"
    p "Total characters: #{number_with_delimiter(total_chars)}"
    p "Avg characters per post: #{number_with_delimiter(avg_chars)} (#{avg_tweets_per_post} tweets)"
    p "Most Frequent Words: #{most_frequent}"
    p "*"*100
  end  

  task :send_hourly_entries => :environment do
    users = User.subscribed_to_emails.not_just_signed_up
    users.each do |user|
      # Check if it's the hour they want where they live AND the day where they live that they want it sent: send it.
      if Time.now.in_time_zone(user.send_timezone).hour == user.send_time.hour && user.frequency.include?(Time.now.in_time_zone(user.send_timezone).strftime('%a'))
        # don't keep emailing if we've already sent 3 emails (welcome + 2 weeklys) and the user is not using the service (should decrease spam reports)
        if user.emails_sent > 4 && user.entries.count == 0 && ENV['FREE_WEEK'] != 'true'
          user.update_columns(frequency: nil)
        else
          # Every other week for free users
          if user.is_pro? || (user.is_free? && Time.now.strftime("%U").to_i % 2 == 0)
            begin
              EntryMailer.send_entry(user).deliver_now
            rescue StandardError => e
              Rails.logger.warn("Error sending email to #{user.email}: #{e}")
            end
          end
        end
      end
    end
  end

end
