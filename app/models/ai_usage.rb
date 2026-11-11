# Tokens and cost of one AI reflection (Entry::AiAssistant), for the admin's
# per-user AI cost. Holds no entry text.
class AiUsage < ActiveRecord::Base
  belongs_to :user

  validates :model, presence: true

  # Logs a RubyLLM response. Never raises: a logging failure shouldn't cost
  # the writer their reflection.
  def self.record(user:, response:, requested_model:)
    tokens = response.tokens
    create!(
      user: user,
      model: response.model.presence || requested_model,
      input_tokens: tokens&.input.to_i,
      output_tokens: tokens&.output.to_i,
      cost_usd: response.cost&.total
    )
  rescue StandardError => e
    Sentry.capture_exception(e, level: :warning)
    nil
  end
end
