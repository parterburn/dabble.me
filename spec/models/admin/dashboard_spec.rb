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
      Payment.last.update_columns(date: 40.days.ago)

      items = described_class.new.attention_items

      expect(items.first).to include("overdue for a renewal payment")
      expect(items).to include(a_string_matching(/ARR is .+ below the \$20k target/))
    end
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
end
