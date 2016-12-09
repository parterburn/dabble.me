namespace :referrers do

  # Example referrer link: https://dabble.me/?ref=dit1
  task :send_updates => :environment do
    referrers = { '*' => 'hello@dabble.me' }
    if ENV['REFERRERS'].present?
      referrers.merge!(JSON.parse(ENV['REFERRERS']))
    end

    if Time.now.monday?
      referrers.each do |id, email|
        begin        
          UserMailer.referred_users(id, email).deliver_later
        rescue StandardError => e
          Rails.logger.warn("Error sending email to #{email}: #{e}")
        end          
      end
    end
  end

end
