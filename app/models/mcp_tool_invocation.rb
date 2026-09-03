class McpToolInvocation < ActiveRecord::Base
  SOURCES = %w[oauth webmcp].freeze

  belongs_to :user

  validates :tool_name, presence: true
  validates :source, presence: true, inclusion: { in: SOURCES }

  scope :since, ->(time) { where('created_at >= ?', time) }
  scope :on_day, ->(date) { where(created_at: date.all_day) }
  scope :successful, -> { where(success: true) }
end
