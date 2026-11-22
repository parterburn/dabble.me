# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppleSubscription do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  # Signed a minute ago: Apple's signedDate is whole milliseconds, so a stored "now" could
  # outrank an answer signed in the same millisecond, and the answer would be ignored.
  def subscription(**attrs)
    described_class.create!({ user: user, original_transaction_id: SecureRandom.hex(6), environment: "Sandbox",
                              product_id: AppStore::MONTHLY_PRODUCT_ID, status: 1, expires_at: 1.day.from_now,
                              ownership_type: "PURCHASED", state_signed_at: 1.minute.ago }.merge(attrs))
  end

  describe "#entitles_pro?" do
    it "is on while paid for" do
      expect(subscription).to be_entitles_pro
    end

    it "is off once the paid period is over" do
      expect(subscription(expires_at: 1.minute.ago)).not_to be_entitles_pro
    end

    it "is on in a billing grace period, and off after it" do
      expect(subscription(status: 4, expires_at: 1.day.ago, grace_period_expires_at: 1.day.from_now)).to be_entitles_pro
      expect(subscription(status: 4, expires_at: 20.days.ago, grace_period_expires_at: 1.day.ago)).not_to be_entitles_pro
    end

    it "is off in billing retry without a grace period" do
      expect(subscription(status: 3, expires_at: 1.day.ago)).not_to be_entitles_pro
    end

    it "is off once refunded or revoked, even with time left, whatever the status says" do
      expect(subscription(revoked_at: Time.current)).not_to be_entitles_pro
      expect(subscription(revoked_at: Time.current, status: nil)).not_to be_entitles_pro
      expect(subscription(status: 5)).not_to be_entitles_pro
    end

    it "is off when Apple says expired, even if the stored date hasn't passed" do
      expect(subscription(status: 2)).not_to be_entitles_pro
    end

    it "is off for Family Sharing" do
      expect(subscription(ownership_type: "FAMILY_SHARED")).not_to be_entitles_pro
    end
  end

  describe "accounts" do
    it "is kept, without its account, when the account is deleted" do
      record = subscription
      user.update_column(:deleted_at, 2.hours.ago)
      DeleteUserJob.perform_now(user.id)
      expect(record.reload.user_id).to be_nil
    end

    it "tells someone deleting their account to cancel in iOS Settings while it's set to renew" do
      subscription(auto_renew: true)
      expect(user.separate_billing_to_cancel).to eq(provider: "Apple", certain: true)
    end

    it "says nothing to cancel once auto-renew is off" do
      user.update!(plan: "Free")
      subscription(auto_renew: false)
      expect(user.separate_billing_to_cancel).to be_nil
    end

    it "says nothing to cancel on an App Store plan that's already cancelled" do
      user.update!(plan: "PRO Monthly Apple")
      subscription(auto_renew: false)
      expect(user.separate_billing_to_cancel).to be_nil
    end

    it "names Apple as the billing provider for an App Store plan" do
      user.update!(plan: "PRO Monthly Apple")
      expect(user.plan_type_unlinked).to eq("Apple")
    end
  end

  describe "the expired-plan check (UserDowngradeExpiredWorker)" do
    it "leaves App Store plans alone, however old their last payment" do
      user.update!(plan: "PRO Monthly Apple")
      subscription
      user.payments.create!(amount: 3.99, date: 3.months.ago, apple_transaction_id: "1")
      UserDowngradeExpiredWorker.new.perform
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "downgrades an expired web plan, and an active App Store subscription takes over" do
      user.update!(plan: "PRO Monthly PayHere")
      subscription
      user.payments.create!(amount: 4, date: 3.months.ago)
      expect(UserMailer).not_to receive(:downgraded) # Still PRO: no "you're on Free" email.
      UserDowngradeExpiredWorker.new.perform
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "doesn't let App Store charges keep a cancelled web plan alive" do
      user.update!(plan: "PRO Monthly PayHere")
      subscription
      user.payments.create!(amount: 4, date: 3.months.ago)
      user.payments.create!(amount: 3.99, date: 2.days.ago, apple_transaction_id: "2")
      UserDowngradeExpiredWorker.new.perform
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "still emails an expired web plan with no App Store subscription" do
      user.update!(plan: "PRO Monthly PayHere")
      user.payments.create!(amount: 4, date: 3.months.ago)
      expect(UserMailer).to receive(:downgraded).with(user, gift: false).and_call_original
      UserDowngradeExpiredWorker.new.perform
      expect(user.reload.plan).to eq("Free")
    end
  end

  describe "the nightly check (AppleSubscriptionRefreshWorker)" do
    it "ends PRO whose paid period ran out with no word from Apple" do
      user.update!(plan: "PRO Monthly Apple")
      subscription(expires_at: 1.hour.ago)
      expect { AppleSubscriptionRefreshWorker.new.perform }.to have_enqueued_mail(UserMailer, :downgraded)
      expect(user.reload.plan).to eq("Free")
    end

    it "asks Apple about each subscription and records the answer" do
      record = subscription(status: 1, expires_at: 1.hour.ago, original_transaction_id: "1000000001")
      renewed = apple_transaction(user: user, expiresDate: ms(1.month.from_now))
      stub_apple_status(renewed)
      with_app_store_api { AppleSubscriptionRefreshWorker.new.perform }
      expect(record.reload.expires_at).to be_within(1.second).of(1.month.from_now)
      expect(user.reload.plan).to eq("PRO Monthly Apple")
    end

    it "still ends PRO on schedule when Apple's API is down" do
      user.update!(plan: "PRO Monthly Apple")
      subscription(expires_at: 1.hour.ago)
      stub_request(:get, %r{/inApps/v1/subscriptions/}).to_return(status: 429)
      with_app_store_api { AppleSubscriptionRefreshWorker.new.perform }
      expect(user.reload.plan).to eq("Free")
    end

    it "carries on past a subscription Apple can't answer about" do
      subscription(original_transaction_id: "1000000001")
      second = subscription(original_transaction_id: "1000000002", expires_at: 1.hour.ago)
      stub_request(:get, %r{/inApps/v1/subscriptions/1000000001}).to_return(status: 503)
      stub_apple_status(apple_transaction(user: user, originalTransactionId: "1000000002", expiresDate: ms(1.month.from_now)))
      with_app_store_api { AppleSubscriptionRefreshWorker.new.perform }
      expect(second.reload.expires_at).to be > 1.week.from_now
    end
  end
end
