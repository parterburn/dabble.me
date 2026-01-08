require "capybara/rails"
require "capybara/rspec"
require "rack/utils"

require "selenium/webdriver"

# Capybara configuration for more stable headless testing
Capybara.configure do |config|
  config.default_max_wait_time = 10 # Increase from default 2 seconds
  config.default_normalize_ws = false
  config.ignore_hidden_elements = true
  config.visible_text_only = true
  config.match = :prefer_exact
  config.exact = false
end

Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new app,
    browser: :chrome
end

Capybara.register_driver :selenium_chrome_headless do |app|
  chrome_options = Selenium::WebDriver::Chrome::Options.new
  chrome_options.add_argument("--headless=new") # Use new headless mode
  chrome_options.add_argument("--no-sandbox")
  chrome_options.add_argument("--disable-dev-shm-usage")
  chrome_options.add_argument("--disable-gpu")
  chrome_options.add_argument("--window-size=1400,1400")
  chrome_options.add_argument("--disable-web-security")
  chrome_options.add_argument("--disable-features=VizDisplayCompositor")
  chrome_options.add_argument("--disable-background-timer-throttling")
  chrome_options.add_argument("--disable-backgrounding-occluded-windows")
  chrome_options.add_argument("--disable-renderer-backgrounding")
  chrome_options.add_argument("--disable-field-trial-config")
  chrome_options.add_argument("--disable-ipc-flooding-protection")

  Capybara::Selenium::Driver.new(app,
    browser: :chrome,
    options: chrome_options)
end

# ENABLE :chrome AS THE DRIVER BELOW FOR DEBUGGING
# Capybara.javascript_driver = :chrome
Capybara.javascript_driver = :selenium_chrome_headless

Capybara.app = Rack::ShowExceptions.new(Dabbleme::Application)
Capybara.server_port = 64515
