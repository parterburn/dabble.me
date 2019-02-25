namespace :user do

  # rake user:downgrade_expired
  task :downgrade_expired => :environment do
    User.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 368.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending yearly downgrade expired email to #{user.email}: #{e}")
      end      
    end

    User.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 33.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending montly downgrade expired email to #{user.email}: #{e}")
      end
    end
  end

  task :downgrade_gumroad_expired => :environment do
    User.gumroad_only.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 368.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending gumroad yearly expired email to #{user.email}: #{e}")
      end        
    end

    User.gumroad_only.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 33.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending gumroad monthly expired email to #{user.email}: #{e}")
      end        
    end
  end 

  task :downgrade_payhere_expired => :environment do
    User.payhere_only.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 368.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending payhere yearly expired email to #{user.email}: #{e}")
      end        
    end

    User.payhere_only.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 33.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending payhere monthly expired email to #{user.email}: #{e}")
      end        
    end
  end   

  task :downgrade_paypal_expired => :environment do
    User.paypal_only.pro_only.yearly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 367.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending yearly paypal expired email to #{user.email}: #{e}")
      end        
    end

    User.paypal_only.pro_only.monthly.not_forever.joins(:payments).having("MAX(payments.date) < ?", 33.days.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      begin
        UserMailer.downgraded(user).deliver_later
      rescue StandardError => e
        Rails.logger.warn("Error sending montly paypal expired email to #{user.email}: #{e}")
      end        
    end
  end

   task :handle_free_week => :environment do
    if ENV['FREE_WEEK'].present?
        User.free_only.select { |u| u.frequency.present? }.each do |user|
          if ENV['FREE_WEEK'] == 'true'
            user.update_column(:frequency, ['Sun', 'Wed', 'Fri'])
          elsif ENV['FREE_WEEK'] == 'false'
            user.update_column(:frequency, ['Sun'])
          end
        end
    end
  end 

end
