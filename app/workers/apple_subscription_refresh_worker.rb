# frozen_string_literal: true

# Nightly: asks Apple for the state of every App Store subscription that gives PRO now or did
# in the last 60 days, in case a notification never arrived (or arrived before the App Store
# Server API had credentials). Then each account's plan follows (AppStore::Entitlement), which
# also ends PRO whose paid period ran out with no word from Apple.
class AppleSubscriptionRefreshWorker
  include Sidekiq::Job

  sidekiq_options retry: false, queue: :default

  def perform
    AppleSubscription.worth_refreshing.or(AppleSubscription.where(user_id: User.apple_only.select(:id)))
                     .find_each do |subscription|
      refresh(subscription)
    end
  end

  private

  def refresh(subscription)
    if AppStore.api_configured?
      AppStore::Subscriptions.refresh!(original_transaction_id: subscription.original_transaction_id,
                                       environment: subscription.environment)
    end
  rescue AppStore::Error, ActiveRecord::ActiveRecordError => e
    Sentry.capture_exception(e, level: :warning, extra: { original_transaction_id: subscription.original_transaction_id })
  ensure
    # Even when Apple couldn't be asked: what's stored still says when the paid period ends.
    begin
      AppStore::Entitlement.sync!(subscription.reload.user)
    rescue ActiveRecord::ActiveRecordError => e
      Sentry.capture_exception(e, extra: { original_transaction_id: subscription.original_transaction_id })
    end
  end
end
