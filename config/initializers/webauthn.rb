WebAuthn.configure do |config|
  # This RP ID should match the domain of your application
  if Rails.env.production?
    config.rp_id = "dabble.me"
    config.origin = "https://dabble.me"
  elsif Rails.env.development?
    config.rp_id = "localhost"
    config.origin = "http://localhost:3000"
  else
    config.rp_id = "test.host"
    config.origin = "http://test.host"
  end
  config.rp_name = "Dabble Me"
end
