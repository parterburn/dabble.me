class BusinessMetricSnapshot < ActiveRecord::Base
  validates :captured_on, presence: true, uniqueness: true

  scope :chronological, -> { order(:captured_on) }

  def net_new_mrr_cents
    gross_new_mrr_cents - churned_mrr_cents
  end

  def arr_gap_cents(target_cents = RevenueMetrics::TARGET_ARR_CENTS)
    target_cents - arr_cents
  end
end
