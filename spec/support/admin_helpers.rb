# frozen_string_literal: true

# Signs an admin in the way they reach admin pages in production: signed in,
# with a passkey confirmed within AdminAccess::PASSKEY_FRESHNESS
# (see spec/requests/admin_access_spec.rb for the check itself).
module AdminControllerHelpers
  def sign_in_admin(user)
    sign_in user
    AdminAccess.record_passkey!(session, user)
  end
end

RSpec.configure do |config|
  config.include AdminControllerHelpers, type: :controller
end
