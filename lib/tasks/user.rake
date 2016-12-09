namespace :user do

  # rake user:downgrade_expired
  task :downgrade_expired => :environment do
    User.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 367.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending email to #{user.email}: #{e}")
      end      
    end

    User.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 32.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending email to #{user.email}: #{e}")
      end
    end
  end

  task :downgrade_gumroad_expired => :environment do
    User.gumroad_only.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 367.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending email to #{user.email}: #{e}")
      end        
    end

    User.gumroad_only.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 32.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending email to #{user.email}: #{e}")
      end        
    end
  end 

  task :downgrade_paypal_expired => :environment do
    User.paypal_only.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 367.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending email to #{user.email}: #{e}")
      end        
    end

    User.paypal_only.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 32.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending email to #{user.email}: #{e}")
      end        
    end
  end

   task :handle_free_week => :environment do
    if ENV['FREE_WEEK'].present?
        User.free_only.each do |user|
          if ENV['FREE_WEEK'] == 'true'
            user.update_column(:frequency, ['Sun', 'Wed', 'Fri'])
          elsif ENV['FREE_WEEK'] == 'false'
            user.update_column(:frequency, ['Sun'])
          end
        end
    end
  end 

end