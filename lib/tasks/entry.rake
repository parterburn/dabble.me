namespace :entry do

  # rake entry:send_entries_test
  task :send_entries_test => :environment do
    user = User.where(:email=>"admin@dabble.ex").first
    EntryMailer.send_entry(user).deliver_now
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
