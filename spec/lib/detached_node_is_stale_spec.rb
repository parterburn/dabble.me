require "rails_helper"

# spec/support/config/capybara.rb
RSpec.describe DetachedNodeIsStale do
  let(:detached) do
    Selenium::WebDriver::Error::UnknownError.new(
      'unknown error: unhandled inspector error: {"code":-32000,"message":"Node with given id does not belong to the document"}'
    )
  end

  it "reports a node Chrome says has left the document as a stale reference, which Capybara retries" do
    expect { described_class.translate { raise detached } }
      .to raise_error(Selenium::WebDriver::Error::StaleElementReferenceError, /does not belong to the document/)
    expect(Capybara::Selenium::Driver.new(nil).invalid_element_errors)
      .to include(Selenium::WebDriver::Error::StaleElementReferenceError)
  end

  it "leaves any other unknown error, and a normal result, alone" do
    other = Selenium::WebDriver::Error::UnknownError.new("unknown error: something else")

    expect { described_class.translate { raise other } }.to raise_error(other)
    expect(described_class.translate { :visible }).to eq(:visible)
  end

  it "wraps the Chrome node's visibility and text checks" do
    wrapped = %i[visible? visible_text all_text]

    expect(Capybara::Selenium::ChromeNode.ancestors.first).to eq(described_class)
    expect(described_class.instance_methods(false)).to match_array(wrapped)
    expect(wrapped).to all(satisfy { |name| Capybara::Selenium::Node.method_defined?(name) })
  end
end
