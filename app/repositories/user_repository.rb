module UserRepository
  extend ActiveSupport::Concern

  included do
    scope :subscribed_to_emails, -> { where("frequency NOT LIKE '%[]%'") }
    scope :not_just_signed_up, -> { where("created_at < (?)", DateTime.now - 18.hours) }
    scope :daily_emails, -> { where(frequency: "---\n- Sun\n- Mon\n- Tue\n- Wed\n- Thu\n- Fri\n- Sat\n") }
    scope :with_entries, -> { includes(:entries).where("entries.id > 0").references(:entries) }
    scope :without_entries, -> { includes(:entries).where("entries.id IS null").references(:entries) }
    scope :free_only, -> { where("plan ILIKE '%free%' OR plan IS null") }
    scope :pro_only, -> { where("plan ILIKE '%pro%'") }
    scope :monthly, -> { where("plan ILIKE '%monthly%'") }
    scope :yearly, -> { where("plan ILIKE '%yearly%'") }
    scope :forever, -> { where("plan ILIKE '%forever%'") }
    scope :payhere_only, -> { where("plan ILIKE '%payhere%'") }
    scope :gumroad_only, -> { where("plan ILIKE '%gumroad%'") }
    scope :paypal_only, -> { where("plan ILIKE '%paypal%'") }
    scope :not_forever, -> { where("plan NOT ILIKE '%forever%'") }
    scope :referrals, -> { where("referrer IS NOT null") }
    # scope :entries_to_approve, -> { where("approved_at IS null") }

    scope :referrals_not_forever, -> { paypal_only.not_forever.referrals }
  end
end