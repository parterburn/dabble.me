namespace :entry do

  # rake entry:send_entries_test
  task :send_entries_test => :environment do
    user = User.where(:email=>"paularterburn@gmail.com").first
    EntryWorker.perform_async(user.id)
  end

  task :send_hourly_entries => :environment do
    users = User.where("date_part('hour', send_time) = ?", Time.now.hour).where(:email=>"paularterburn@gmail.com")
    users.each do |user|
      if Time.now.in_time_zone(user.send_timezone).hour == user.send_time.hour && user.frequency.include?(Time.now.in_time_zone(user.send_timezone).strftime('%a'))
        #It's the hour they want where they live AND the day where they live that they want it sent: send it.
        EntryWorker.perform_async(user.id)
      end
    end
  end

end