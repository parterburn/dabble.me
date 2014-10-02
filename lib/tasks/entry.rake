namespace :entry do

  # rake entry:send_entries
  task :send_entries => :environment do
    users = User.where(:email=>"paularterburn@gmail.com")
    users.each do |user|
      EntryWorker.perform_async(user.id)
    end
  end

  task :send_sat_entries => :environment do
    users = User.where("frequency ~ 'Sat'")
    users.each do |user|
      if Time.now.in_time_zone(user.send_timezone).saturday? && Time.now.in_time_zone(user.send_timezone).hour == user.send_time.hour
        #It's Saturday where they live & in the hour they want it, send it.
        EntryWorker.perform_async(user.id)
      end
    end
  end

  task :send_1pm_entries => :environment do
    users = User.where("date_part('hour', send_time) = 13")
    users.each do |user|
      if Time.now.in_time_zone(user.send_timezone).hour == user.send_time.hour
        #It's 1pm where they live, send it.
        EntryWorker.perform_async(user.id)
      end
    end
  end

end