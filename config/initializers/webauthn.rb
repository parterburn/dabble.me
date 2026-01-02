WebAuthn.configure do |config|
  # This RP ID should match the domain of your application
  if Rails.env.production?
    config.rp_id = "dabble.me"
    config.allowed_origins = ["https://dabble.me"]
  elsif Rails.env.development?
    config.rp_id = "localhost"
    config.allowed_origins = ["http://localhost:3000"]
  else
    config.rp_id = "test.host"
    config.allowed_origins = ["http://test.host"]
  end
  config.rp_name = "Dabble Me"
end
