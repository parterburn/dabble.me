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

  task :update_stripe_id => :environment do
    users_to_update = User.where(stripe_id: [nil, ""]).where.not(payhere_id: [nil, ""])
    return nil unless users_to_update.any?

    Stripe.api_key = ENV['STRIPE_API_KEY']
    stripe_customers = Stripe::Customer.list(limit: 100)

    users_to_update.each do |user|
      stripe_customer = stripe_customers.filter { |cust| cust.metadata[:customer_id] == user.payhere_id }.first
      user.update_attributes(stripe_id: stripe_customer&.id) if stripe_customer.present?
    end    
  end

end
