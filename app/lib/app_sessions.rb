# frozen_string_literal: true

# The iOS app's sign-ins as UserSession rows. Each access token names its row
# (oauth_access_tokens.user_session_id); a refresh hands the name to the new token (the
# after_successful_strategy_response hook in config/initializers/doorkeeper.rb). A token from
# before this shipped, or fresh from sign-in, gets a row on its first API call.
#
# Signing a row out revokes its tokens (UserSession#revoke!). A token that names a row that's
# gone is refused here too, which covers a refresh that raced the sign-out.
module AppSessions
  module_function

  # The token's row, made if it has none; nil when it was signed out.
  def for_token(token, user, request)
    return unless app_token?(token)

    session = if token.user_session_id
                UserSession.ios_app.find_by(id: token.user_session_id, user_id: user.id)
              else
                link_new_session(token, user, request)
              end
    session&.touch_activity!(request)
    session
  end

  def app_token?(token)
    token.application_id.present? && token.application_id == MobileApp.application_id
  end

  # Two first calls at once with the same token: only one row is kept.
  def link_new_session(token, user, request)
    session, = UserSession.start!(user, kind: 'ios_app', request: request)
    linked = Doorkeeper::AccessToken.where(id: token.id, user_session_id: nil)
                                    .update_all(user_session_id: session.id)
    return session.tap { token.user_session_id = session.id } if linked == 1

    session.destroy
    token.reload
    UserSession.ios_app.find_by(id: token.user_session_id, user_id: user.id)
  end

  # Called after a refresh: the new token stays on the old one's row.
  def carry_over(old_token, new_token)
    return unless old_token&.user_session_id && new_token&.persisted?

    new_token.update_column(:user_session_id, old_token.user_session_id)
  end
end
