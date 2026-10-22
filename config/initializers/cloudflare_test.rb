if Rails.env.test?
  # Set CloudflareRails IPs manually to avoid external HTTP requests during tests
  Rails.application.config.after_initialize do
    test_ips = [IPAddr.new('127.0.0.1/32'), IPAddr.new('::1/128')].freeze
    CloudflareRails::Importer.instance_variable_set(:@ips, test_ips)
    CloudflareRails::Importer.singleton_class.define_method(:cloudflare_ips) do |refresh: false|
      test_ips
    end
  end
end
