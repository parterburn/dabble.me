require "rails_helper"

RSpec.describe Admin::Dashboard do
  include ActiveSupport::Testing::TimeHelpers

  def create_pro(plan:, amount:, **attrs)
    user = create(:user, plan: plan, **attrs)
    create(:payment, user: user, amount: amount, date: 5.days.ago) if amount
    user
  end

  it "puts overdue renewals ahead of the standing $20k ARR gap" do
    travel_to Time.zone.parse("2026-09-02 12:00:00") do
      create_pro(plan: "PRO Monthly PayHere", amount: 4, created_at: 60.days.ago)
      Payment.last.update_columns(date: 50.days.ago)

      items = described_class.new.attention_items

      expect(items.first).to include("overdue for a renewal payment")
      expect(items).to include(a_string_matching(/ARR is .+ below the \$20k target/))
    end
  end

  it "does not flag a yearly subscriber before 15 days past the renewal date" do
    travel_to Time.zone.parse("2026-09-07 12:00:00") do
      create_pro(plan: "PRO Yearly PayHere", amount: 40, created_at: 2.years.ago)
      Payment.last.update_columns(date: 340.days.ago)

      items = described_class.new.attention_items

      expect(items).not_to include(a_string_matching(/overdue for a renewal payment/))
    end
  end

  it "flags churned MRR without waiting for a week-old snapshot" do
    create_pro(plan: "PRO Monthly PayHere", amount: 4)
    allow(BusinessMetrics::MailgunStats).to receive(:fetch).and_return(
      BusinessMetrics::MailgunStats::Result.new(sent: 0, failed: 0, opened: 0, complained: 0)
    )
    BusinessMetrics::Capture.call(on: Date.yesterday)
    User.pro_only.update_all(plan: "Free")
    BusinessMetrics::Capture.call(on: Date.current)

    items = described_class.new.attention_items

    expect(items.first).to eq("Churned MRR exceeded new MRR on the latest snapshot.")
  end

  it "hides empty unknown and lifetime cohorts" do
    create_pro(plan: "PRO Monthly PayHere", amount: 4)

    labels = described_class.new.pricing_cohorts.map { |row| row[:label] }

    expect(labels).to include("New monthly ($4)")
    expect(labels).not_to include("Monthly (unknown price)")
    expect(labels).not_to include("Lifetime (excluded from MRR)")
  end

  it "counts PRO users with no entry in 30 days as inactive" do
    writer = create_pro(plan: "PRO Monthly PayHere", amount: 4)
    create(:entry, user: writer, date: 2.days.ago, body: "today")
    create_pro(plan: "PRO Monthly PayHere", amount: 4)

    dashboard = described_class.new

    expect(dashboard.paid_inactive_30d).to eq(1)
    expect(dashboard.retention[:pro_7d]).to eq(1)
  end

  it "uses mature cohorts for 72-hour first-entry activation" do
    travel_to Time.zone.parse("2026-09-02 12:00:00") do
      mature = create(:user, plan: "Free", created_at: 10.days.ago)
      create(:entry, user: mature, created_at: 9.days.ago, date: 9.days.ago, body: "first")
      create(:user, plan: "Free", created_at: 1.hour.ago)

      expect(described_class.new.first_entry_activation_rate).to eq(1.0)
    end
  end

  it "reports live MCP connected users and call volume" do
    user = create_pro(plan: "PRO Monthly PayHere", amount: 4)
    app = Doorkeeper::Application.create!(
      name: "Inspector",
      uid: "dashboard-mcp-client",
      redirect_uri: "http://127.0.0.1/cb",
      scopes: "mcp:access",
      confidential: false
    )
    Doorkeeper::AccessToken.create!(
      resource_owner_id: user.id,
      application_id: app.id,
      scopes: "mcp:access",
      expires_in: 2.hours
    )
    create(:mcp_tool_invocation, user: user, tool_name: "analyze_entries")

    mcp = described_class.new.mcp

    expect(mcp[:connected_now]).to eq(1)
    expect(mcp[:calls_30d]).to eq(1)
    expect(mcp[:tools].first[:name]).to eq("analyze_entries")
  end

  it "counts first payments ever and orders upgrade weeks by calendar date" do
    travel_to Time.zone.parse("2026-09-02 12:00:00") do
      july_upgrade = create(:user, plan: "PRO Monthly PayHere")
      create(:payment, user: july_upgrade, amount: 4, date: Time.zone.parse("2026-07-28 10:00:00"))

      august_upgrade = create(:user, plan: "PRO Monthly PayHere")
      create(:payment, user: august_upgrade, amount: 4, date: Time.zone.parse("2026-08-12 10:00:00"))

      canceled = create(:user, plan: "Free")
      create(:payment, user: canceled, amount: 4, date: Time.zone.parse("2026-08-20 10:00:00"))

      veteran = create(:user, plan: "PRO Monthly PayHere")
      create(:payment, user: veteran, amount: 3, date: Time.zone.parse("2026-01-10 10:00:00"))
      create(:payment, user: veteran, amount: 4, date: Time.zone.parse("2026-08-15 10:00:00"))

      chart = described_class.new.chart_upgrades

      expect(chart.values.sum).to eq(3)
      expect(chart.keys).to eq(["Jul 26", "Aug 09", "Aug 16"])
      expect(chart["Jul 26"]).to eq(1)
      expect(chart["Aug 09"]).to eq(1)
      expect(chart["Aug 16"]).to eq(1)
    end
  end
end
