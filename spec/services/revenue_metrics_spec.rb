require "rails_helper"

RSpec.describe RevenueMetrics do
  def create_pro(plan:, amount:, **attrs)
    user = create(:user, plan: plan, **attrs)
    create(:payment, user: user, amount: amount, date: 2.days.ago) if amount
    user
  end

  describe "#mrr_cents / #arr_cents" do
    it "uses cents and does not truncate monthly plus yearly like the old to_i formula" do
      create_pro(plan: "PRO Monthly PayHere", amount: 3.99)
      create_pro(plan: "PRO Yearly PayHere", amount: 40)

      metrics = described_class.current

      # Old formula: 3.99.to_i + (40.to_i / 12) => 3 + 3 = 6
      expect(metrics.mrr_cents).to eq(399 + (4000 / 12.0).round)
      expect(metrics.arr_cents).to eq((399 * 12) + 4000)
    end

    it "excludes lifetime plans from MRR even if they have a payment" do
      create_pro(plan: "PRO Forever", amount: 100)
      create_pro(plan: "PRO Monthly PayHere", amount: 4)

      metrics = described_class.current

      expect(metrics.lifetime_subscriber_count).to eq(1)
      expect(metrics.recurring_subscriber_count).to eq(1)
      expect(metrics.mrr_cents).to eq(400)
      expect(metrics.arr_cents).to eq(4800)
    end

    it "splits legacy $3/$30 from new $4/$40" do
      create_pro(plan: "PRO Monthly PayHere", amount: 3)
      create_pro(plan: "PRO Monthly PayHere", amount: 4)
      create_pro(plan: "PRO Yearly PayHere", amount: 30)
      create_pro(plan: "PRO Yearly PayHere", amount: 40)

      breakdown = described_class.current.plan_breakdown

      expect(breakdown["legacy_monthly"]["count"]).to eq(1)
      expect(breakdown["new_monthly"]["count"]).to eq(1)
      expect(breakdown["legacy_yearly"]["count"]).to eq(1)
      expect(breakdown["new_yearly"]["count"]).to eq(1)
      expect(breakdown["legacy_monthly"]["mrr_cents"]).to eq(300)
      expect(breakdown["new_yearly"]["arr_cents"]).to eq(4000)
    end

    it "ignores free users and deleted PRO users" do
      create(:user, plan: "Free")
      deleted = create_pro(plan: "PRO Monthly PayHere", amount: 4)
      deleted.update_column(:deleted_at, Time.current)

      expect(described_class.current.recurring_subscriber_count).to eq(0)
    end
  end
end
