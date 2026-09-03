require "rails_helper"

RSpec.describe FounderWeeklyDigestWorker do
  include ActiveSupport::Testing::TimeHelpers

  before do
    allow(BusinessMetrics::MailgunStats).to receive(:fetch).and_return(
      BusinessMetrics::MailgunStats::Result.new(sent: 0, failed: 0, opened: 0, complained: 0)
    )
    ActionMailer::Base.deliveries.clear
  end

  it "sends the weekly founder digest" do
    create(:user, admin: true, email: "admin@example.com", plan: "PRO Forever")
    create(:business_metric_snapshot, captured_on: Date.parse("2026-08-31"), arr_cents: 1_500_000, mrr_cents: 125_000)
    ActionMailer::Base.deliveries.clear

    travel_to Time.zone.parse("2026-09-07 06:00:00") do # Monday
      described_class.new.perform
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      email = ActionMailer::Base.deliveries.last
      expect(email.to).to include("admin@example.com")
      expect(email.subject).to include("Dabble Me weekly")
      expect(email.body.encoded).to include("Needs attention")
    end
  end
end
