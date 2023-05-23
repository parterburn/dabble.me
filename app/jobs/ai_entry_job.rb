class AiEntryJob < ActiveJob::Base
  queue_as :default

  def perform(user_id, entry_id, email: true)
    return nil if ::Rails.env.test?

    user = User.find(user_id)
    entry = user.entries.find(entry_id)

    if email
      EntryMailer.respond_as_ai(user, entry).deliver_now
    else
      ai_answer = entry.ai_response
      return unless ai_answer.present?

      entry.body = "#{entry.body}<hr><strong>🤖 DabbleMeGPT:</strong><br/>#{ActionController::Base.helpers.simple_format(ai_answer.gsub(/<hr\/?>/, "").gsub(/\A\n*/, ""), {}, sanitize: false)}"
      entry.save
    end
  end
end
