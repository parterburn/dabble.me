namespace :entry do

  # rake entry:send_entries_test
  task :send_entries_test => :environment do
    user = User.where(:email=>"paularterburn@gmail.com").first
    EntryWorker.perform_async(user.id)
  end

  task :send_hourly_entries => :environment do
    users = User.subscribed_to_emails.not_just_signed_up
    total_sent_before = users.sum(:emails_sent)
    sent_this_session = 0
    users.each do |user|
      if Time.now.in_time_zone(user.send_timezone).hour == user.send_time.hour && user.frequency.include?(Time.now.in_time_zone(user.send_timezone).strftime('%a'))
        #It's the hour they want where they live AND the day where they live that they want it sent: send it.
        EntryWorker.perform_async(user.id)
        sent_this_session += 1
      end
    end

    if ENV['SEND_REPORT'] && ENV['SEND_REPORT'] == "yes"
      EntryMailer.delay_for(10.minutes, retry: 3, queue: "entry").sent_report(total_sent_before, sent_this_session, Time.now)
    end

  end

end