# Per-request state, reset by Rails between requests.
class Current < ActiveSupport::CurrentAttributes
  # The device making this request (UserSession), set by WebSessions or Api::V1::BaseController.
  attribute :user_session
end
