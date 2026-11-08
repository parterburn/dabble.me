# frozen_string_literal: true

# WebMock is required by specs that stub HTTP; `webmock/rspec` enables interception for the process.
# Re-apply defaults in `before(:each)` because `WebMock.reset!` (from webmock/rspec) clears stubs after every example.
require 'webmock/rspec'

RSpec.configure do |config|
  config.before(:each) do
    WebMock.disable_net_connect!(allow_localhost: true)

    WebMock.stub_request(:get, %r{\Ahttps://www\.cloudflare\.com/ips-v}).to_return(
      status: 200,
      body: "10.0.0.0\n",
      headers: { 'Content-Type' => 'text/plain' }
    )

    # Pages load Slab icons from /icons/slab/, which IconsController fetches from S3.
    WebMock.stub_request(:get, %r{\Ahttps://dabble-me\.s3\.amazonaws\.com/uploads/icons/slab/[a-z0-9-]+\.svg\z}).to_return(
      status: 200,
      body: %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 576"><path d="M0 0h576v576H0z"/></svg>),
      headers: { 'Content-Type' => 'image/svg+xml' }
    )

    WebMock.stub_request(:post, %r{\Ahttps://challenges\.cloudflare\.com/turnstile/}).to_return(
      status: 200,
      body: { success: true }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end
end
