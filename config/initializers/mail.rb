ActionMailer::Base.smtp_settings = {
  :user_name => ENV['MAILGUN_USERNAME'],
  :password => ENV['MAILGUN_PASSWORD'],
  :domain => ENV['MAIN_DOMAIN'],
  :address => 'smtp.mailgun.org',
  :port => 587,
  :authentication => :plain,
  :enable_starttls_auto => true
}