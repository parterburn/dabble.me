require "rails_helper"

RSpec.describe CaptureBusinessMetricsWorker do
  include ActiveSupport::Testing::TimeHelpers

  before do
    allow(BusinessMetrics::MailgunStats).to receive(:fetch).and_return(
      BusinessMetrics::MailgunStats::Result.new(sent: 0, failed: 0, opened: 0, complained: 0)
    )
    ActionMailer::Base.deliveries.clear
  end

  it "captures yesterday before expired-plan downgrades run" do
    create(:user, admin: true, email: "admin@example.com")
    ActionMailer::Base.deliveries.clear

    travel_to Time.zone.parse("2026-09-02 00:05:00") do # Wednesday
      expect { described_class.new.perform }.to change(BusinessMetricSnapshot, :count).by(1)
      expect(BusinessMetricSnapshot.last.captured_on).to eq(Date.parse("2026-09-01"))
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it "does not send the weekly digest" do
    create(:user, admin: true, email: "admin@example.com", plan: "PRO Forever")
    ActionMailer::Base.deliveries.clear

    travel_to Time.zone.parse("2026-09-07 00:05:00") do # Monday
      described_class.new.perform
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it "attributes overnight expired-plan downgrades to the new day, not yesterday" do
    travel_to Time.zone.parse("2026-09-01 12:00:00") do
      user = create(:user, plan: "PRO Monthly PayHere")
      create(:payment, user: user, amount: 4, date: 5.days.ago)
      BusinessMetrics::Capture.call(on: Date.current)
    end

    travel_to Time.zone.parse("2026-09-02 00:05:00") do
      described_class.new.perform
      tuesday = BusinessMetricSnapshot.find_by!(captured_on: Date.parse("2026-09-01"))
      expect(tuesday.canceled_subscriber_count).to eq(0)
      expect(tuesday.recurring_subscriber_count).to eq(1)
    end

    travel_to Time.zone.parse("2026-09-02 00:30:00") do
      User.pro_only.update_all(plan: "Free")
    end

    travel_to Time.zone.parse("2026-09-03 00:05:00") do
      described_class.new.perform
      tuesday = BusinessMetricSnapshot.find_by!(captured_on: Date.parse("2026-09-01"))
      wednesday = BusinessMetricSnapshot.find_by!(captured_on: Date.parse("2026-09-02"))
      expect(tuesday.canceled_subscriber_count).to eq(0)
      expect(wednesday.canceled_subscriber_count).to eq(1)
      expect(wednesday.recurring_subscriber_count).to eq(0)
    end
  end
end
