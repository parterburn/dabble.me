# frozen_string_literal: true

# A Dabble Me PRO subscription bought in the iOS app, as Apple last described it. Its user is
# whoever's apple_account_token the latest purchase carried (see AppStore::Claim); it's nil when
# no account has claimed it yet, or the account was deleted.
class AppleSubscription < ActiveRecord::Base
  belongs_to :user, optional: true

  # Unique in the database (create_or_find_by! relies on that, not on a validation).
  validates :original_transaction_id, presence: true
  validates :environment, inclusion: { in: [AppStore::PRODUCTION, AppStore::SANDBOX] }
  validates :product_id, presence: true

  # Rows the nightly check looks at: anything that gives PRO now, or did lately.
  scope :worth_refreshing, -> { where("expires_at > ? OR grace_period_expires_at > ?", 60.days.ago, 60.days.ago) }

  # Whether this subscription gives its account PRO right now. Off once refunded or revoked,
  # for Family Sharing, and once both the paid period and any billing grace period are over.
  # Apple's billing retry without a grace period gives nothing: the customer hasn't paid.
  def entitles_pro?(now: Time.current)
    return false if revoked_at.present?
    return false if ownership_type == AppStore::Snapshot::FAMILY_SHARED
    return false if [AppStore::Snapshot::STATUS_EXPIRED, AppStore::Snapshot::STATUS_REVOKED].include?(status)

    (expires_at.present? && expires_at > now) ||
      (grace_period_expires_at.present? && grace_period_expires_at > now)
  end

  def yearly?
    product_id == AppStore::YEARLY_PRODUCT_ID
  end

  def plan_name
    "PRO #{yearly? ? 'Yearly' : 'Monthly'} Apple"
  end

  def sandbox?
    environment == AppStore::SANDBOX
  end

  def in_grace_period?(now: Time.current)
    status == AppStore::Snapshot::STATUS_GRACE_PERIOD && grace_period_expires_at.present? && grace_period_expires_at > now
  end

  # Takes on what the snapshot says, unless what's stored was signed later (a notification
  # that arrived out of order, or a stale copy of a transaction). Returns whether it changed.
  # Call inside a lock on this row (AppStore::Claim does).
  def apply(snapshot)
    signed_at = snapshot.signed_at
    return false if signed_at.nil?
    return false if persisted? && state_signed_at.present? && signed_at < state_signed_at
    # An upgrade's old transaction says nothing about the subscription now.
    return false if snapshot.upgraded?

    assign_attributes(
      environment: snapshot.environment,
      product_id: snapshot.product_id,
      last_transaction_id: snapshot.transaction_id,
      ownership_type: snapshot.ownership_type,
      status: snapshot.status,
      expires_at: snapshot.expires_at,
      revoked_at: snapshot.revoked_at,
      state_signed_at: signed_at
    )
    self.app_account_token = snapshot.app_account_token if snapshot.app_account_token
    # Renewal info comes with Apple's API answers and most notifications, not with the
    # transaction the app sends: what's known stays until Apple says otherwise.
    if snapshot.renewal
      self.grace_period_expires_at = snapshot.grace_period_expires_at
      self.auto_renew = snapshot.auto_renew
      self.auto_renew_product_id = snapshot.auto_renew_product_id
    end
    save!
    true
  end
end
