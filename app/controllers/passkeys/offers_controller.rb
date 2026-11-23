# frozen_string_literal: true

# The page after a web sign-in that asks an account with no passkey to add one (PasskeyOffer has
# the rules). "Add a passkey" makes one right here, through Passkeys::RegistrationsController;
# "Not now" goes on to wherever the sign-in was headed. It counts as shown once it's shown.
class Passkeys::OffersController < ApplicationController
  before_action :authenticate_user!

  def show
    @continue_to = PasskeyOffer.safe_path(session[PasskeyOffer::RETURN_TO]) ||
                   signed_in_root_path(current_user)
    return redirect_to(@continue_to) if current_user.webauthn_credentials.exists?

    PasskeyOffer.offered!(current_user, cookies, secure: request.ssl?)
    @device = UserAgentLabel.parse(request.user_agent)
  end
end
