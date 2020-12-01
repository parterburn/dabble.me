class Review < ActiveRecord::Base
  STATUSES = %w[new approved changes_requested].freeze

  belongs_to :entry
  belongs_to :user

  validates :review_body, length: { maximum: 140 },
                          presence: true, unless: -> { new? }

  def approved?
    status == 'approved'
  end

  def new?
    status == 'new'
  end
end
