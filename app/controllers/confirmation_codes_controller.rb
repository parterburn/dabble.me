# Emails a code to a signed-in account that has no password (made by email code, EmailSignIn),
# to type where Account Security and the delete page would ask for the password. The app's is
# Api::V1::ConfirmationCodesController.
class ConfirmationCodesController < ApplicationController
  before_action :authenticate_user!

  # POST /users/confirmation_code
  def create
    case EmailCode.send_confirmation(current_user)
    when :ok then flash[:notice] = "We emailed a code to #{current_user.email}. Enter it below."
    when :too_soon then flash[:alert] = 'We just sent a code. Give it a minute to arrive.'
    else flash[:alert] = 'Too many codes. Try again in an hour.'
    end
    redirect_back(fallback_location: security_path)
  end
end
