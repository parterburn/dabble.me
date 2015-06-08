namespace :user do

  # rake user:downgrade_expired
  task :downgrade_expired => :environment do
    User.pro_only.not_forever.joins(:payments).having("MAX(payments.date) < ?", 1.year.ago).group("users.id").each do |user|
      user.update(plan: "Free")
      UserMailer.downgraded(user)
    end
  end

end