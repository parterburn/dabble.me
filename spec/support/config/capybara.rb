require "capybara/rails"
require "capybara/rspec"
require "rack/utils"
require "byebug"

require "selenium/webdriver"

Capybara.register_driver :chrome do |app|
  Capybara::Selenium::Driver.new app,
    browser: :chrome
end

Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--window-size=1440,1024")
  options.add_argument("--headless=new")
  options.add_argument("--disable-gpu") # Temporarily needed if running on Windows.
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-dev-shm-usage")

  Capybara::Selenium::Driver.new(app,
    browser: :chrome,
    options: options
  )
end

# ENABLE :chrome AS THE DRIVER BELOW FOR DEBUGGING
# Capybara.javascript_driver = :chrome
Capybara.javascript_driver = :selenium_chrome_headless

Capybara.app = Rack::ShowExceptions.new(Dabbleme::Application)
Capybara.server_port = 64515
Capybara.default_max_wait_time = 60
