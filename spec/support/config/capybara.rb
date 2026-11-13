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
  # Behave like a desktop with a mouse. Without a pointing device, headless
  # Chrome matches the (hover: none) media query, as a phone does.
  chrome_options.add_argument("--blink-settings=primaryHoverType=2,availableHoverTypes=2,primaryPointerType=4,availablePointerTypes=4")
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

# Since Chrome 156, asking about a node that a navigation or re-render has
# just removed fails with "unknown error ... Node with given id does not
# belong to the document" where it used to be a stale element reference.
# Capybara waits and looks again after a stale reference, but lets an unknown
# error through, so a check made while a page was changing failed outright
# (seen in the photo picker's remove-and-save spec, right after its form is
# submitted). Report it as the stale reference it is, and Capybara retries.
module DetachedNodeIsStale
  DETACHED = "does not belong to the document"

  def self.translate
    yield
  rescue Selenium::WebDriver::Error::UnknownError => e
    raise unless e.message.include?(DETACHED)

    raise Selenium::WebDriver::Error::StaleElementReferenceError, e.message
  end

  %i[visible? visible_text all_text].each do |name|
    define_method(name) { |*args, &block| DetachedNodeIsStale.translate { super(*args, &block) } }
  end
end

require "capybara/selenium/node"
require "capybara/selenium/nodes/chrome_node"
Capybara::Selenium::ChromeNode.prepend(DetachedNodeIsStale)
