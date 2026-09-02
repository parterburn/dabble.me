require "rails_helper"

RSpec.describe BusinessMetrics::Capture do
  before do
    allow(BusinessMetrics::MailgunStats).to receive(:fetch).and_return(
      BusinessMetrics::MailgunStats::Result.new(sent: 10, failed: 1, opened: 4, complained: 0)
    )
  end

  def create_pro(plan:, amount:, referrer: nil)
    user = create(:user, plan: plan, referrer: referrer, emails_sent: 1)
    create(:payment, user: user, amount: amount, date: 5.days.ago)
    user
  end

  it "is idempotent for a given date" do
    create_pro(plan: "PRO Monthly PayHere", amount: 4)

    first = described_class.call(on: Date.current)
    second = described_class.call(on: Date.current)

    expect(BusinessMetricSnapshot.count).to eq(1)
    expect(first.id).to eq(second.id)
    expect(second.mrr_cents).to eq(400)
    expect(second.arr_cents).to eq(4800)
  end

  it "records new and churned subscribers against the previous snapshot" do
    kept = create_pro(plan: "PRO Monthly PayHere", amount: 4)
    leaving = create_pro(plan: "PRO Monthly PayHere", amount: 3)

    described_class.call(on: Date.yesterday)

    leaving.update!(plan: "Free")
    create_pro(plan: "PRO Yearly PayHere", amount: 40)

    snapshot = described_class.call(on: Date.current)

    expect(snapshot.new_subscriber_count).to eq(1)
    expect(snapshot.canceled_subscriber_count).to eq(1)
    expect(snapshot.gross_new_mrr_cents).to eq((4000 / 12.0).round)
    expect(snapshot.churned_mrr_cents).to eq(300)
    expect(snapshot.recurring_subscriber_count).to eq(2)
    expect(snapshot.subscriber_map.keys).to include(kept.id.to_s)
    expect(snapshot.subscriber_map.keys).not_to include(leaving.id.to_s)
  end

  it "counts email replies from inbound journal entries" do
    user = create(:user, plan: "Free")
    create(:entry, user: user, original_email_body: "<p>Hello</p>", created_at: Time.current, date: Time.current)

    snapshot = described_class.call(on: Date.current)

    expect(snapshot.email_sent_count).to eq(10)
    expect(snapshot.email_failed_count).to eq(1)
    expect(snapshot.email_replies_count).to eq(1)
    expect(snapshot.email_reply_rate.to_f).to eq(0.1)
  end
end
