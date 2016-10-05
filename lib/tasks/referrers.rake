namespace :referrers do

  # Example referrer link: https://dabble.me/?ref=dit1
  REFERRERS = {
    '*'             => 'hello@dabble.me'
  }.merge(JSON.parse(ENV['REFERRERS'])).freeze

  task :send_updates => :environment do
    if Time.now.monday?
      REFERRERS.each do |id, email|
        UserMailer.referred_users(id, email).deliver_later
      end
    end
  end

end
