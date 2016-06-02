IntercomRails.config do |config|
  # == Intercom app_id
  #
  config.app_id = ENV["INTERCOM_APP_ID"]

  # == Intercom session_duration
  #
  # config.session_duration = 300000

  # == Intercom secret key
  # This is required to enable secure mode, you can find it on your Setup
  # guide in the "Secure Mode" step.
  #
  config.api_secret = Rails.application.secrets.intercom_api_secret

  # == Intercom API Key
  # This is required for some Intercom rake tasks like importing your users;
  # you can generate one at https://app.intercom.io/apps/api_keys.
  #
  config.api_key = ENV["INTERCOM_API_KEY"]

  # == Enabled Environments
  # Which environments is auto inclusion of the Javascript enabled for
  #
  config.enabled_environments = ["development", "production"]

  # == User Custom Data
  # A hash of additional data you wish to send about your users.
  # You can provide either a method name which will be sent to the current
  # user object, or a Proc which will be passed the current user.
  #
  config.user.custom_data = {
    :user_id => Proc.new { |current_user| current_user.id },
    :user_key => Proc.new { |current_user| current_user.user_key },
    :name => Proc.new { |current_user| current_user.full_name },
    :entries => Proc.new { |current_user| current_user.entries.count },
    :plan => Proc.new { |current_user| current_user.plan },
    :frequency => Proc.new { |current_user| current_user.frequency.join(', ') },
    :timezone => Proc.new { |current_user| current_user.send_timezone }
  }

  # == Custom Style
  # By default, Intercom will add a button that opens the messenger to
  # the page. If you'd like to use your own link to open the messenger,
  # uncomment this line and clicks on any element with id 'Intercom' will
  # open the messenger.
  #
  # config.inbox.style = :custom
  #
  # If you'd like to use your own link activator CSS selector
  # uncomment this line and clicks on any element that matches the query will
  # open the messenger
  # config.inbox.custom_activator = '.intercom'
end
