if Rails.env.test?
  # Skip live Cloudflare IP fetches (avoids Net::HTTP during tests and WebMock conflicts).
  Rails.application.config.after_initialize do
    CloudflareRails::Importer.define_singleton_method(:cloudflare_ips) do |refresh: false|
      @ips = nil if refresh
      @ips ||= (CloudflareRails::FallbackIps::IPS_V4 + CloudflareRails::FallbackIps::IPS_V6).freeze
    end
  end
end
