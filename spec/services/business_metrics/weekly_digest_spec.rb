require "rails_helper"

RSpec.describe BusinessMetrics::WeeklyDigest do
  around do |example|
    previous = ENV["FOUNDER_DIGEST_EMAIL"]
    ENV["FOUNDER_DIGEST_EMAIL"] = "founder@example.com"
    example.run
    ENV["FOUNDER_DIGEST_EMAIL"] = previous
  end

  it "emails admins plus FOUNDER_DIGEST_EMAIL" do
    create(:user, admin: true, email: "admin@example.com")
    ActionMailer::Base.deliveries.clear

    described_class.call

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.last.to).to match_array(%w[admin@example.com founder@example.com])
  end
end
