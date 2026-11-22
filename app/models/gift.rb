# A gifted year of PRO, from a link like dabble.me/gift/<code>.
#
# GIFT_CODES lists the codes that work, comma-separated and case-insensitive:
# "family2026, friends:25". A ":<number>" suffix caps that code at that many
# redemptions; without one a code works until it's removed from the list.
# Removing a code retires the link (it then sends people to the regular
# sign-up) but never takes PRO away from anyone who already redeemed it.
#
# Redeeming puts the account on PLAN for LENGTH. UserDowngradeExpiredWorker
# moves it back to Free once the year is up, and the person can subscribe
# like anyone else. An account can redeem one gift, ever.
class Gift
  PLAN = "PRO Gift".freeze
  LENGTH = 1.year
  VALUE = "$40".freeze

  attr_reader :code, :limit

  def self.find(raw)
    wanted = normalize(raw)
    return if wanted.blank?

    gift = all.find { |g| ActiveSupport::SecurityUtils.secure_compare(g.code, wanted) }
    gift if gift&.available?
  end

  def self.all
    ENV.fetch("GIFT_CODES", "").split(",").filter_map do |entry|
      code, cap = entry.split(":", 2)
      code = normalize(code)
      next if code.blank?

      limit = nil
      unless cap.nil?
        limit = Integer(cap.strip, exception: false)
        # A typo in the cap must not quietly make the code unlimited: skip it.
        if limit.nil? || limit <= 0
          Rails.logger.warn("GIFT_CODES: skipping a code whose cap isn't a positive whole number")
          next
        end
      end
      new(code, limit)
    end
  end

  def self.normalize(raw)
    raw.to_s.strip.downcase
  end

  def initialize(code, limit = nil)
    @code = code
    @limit = limit
  end

  def available?
    limit.nil? || GiftRedemption.where(code: code).count < limit
  end

  # Not for an account that already has PRO (it would end a paid plan's
  # billing link) or one that has had a gift before.
  def redeemable_by?(user)
    !user.is_pro? && !GiftRedemption.exists?(user_id: user.id)
  end

  def redeem!(user)
    return false unless redeemable_by?(user)

    redeemed = false
    User.transaction do
      # Two sign-ups racing for a capped code's last place: take turns, then check again.
      if limit
        User.connection.execute(User.sanitize_sql(["SELECT pg_advisory_xact_lock(hashtext(?))", "gift:#{code}"]))
        raise ActiveRecord::Rollback unless available?
      end
      GiftRedemption.create!(user: user, code: code, expires_at: LENGTH.from_now)
      user.update!(plan: PLAN)
      # Same as a paid upgrade: put back the email days the Free plan cut to Sunday.
      user.update!(frequency: user.previous_frequency) if Array(user.previous_frequency).any?
      redeemed = true
    end
    redeemed
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    user.reload if user.persisted?
    false
  end
end
