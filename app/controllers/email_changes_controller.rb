# Finishing an email change from Account Security. RegistrationsController#update holds the new
# address in users.pending_email and emails a code there; entering it here moves the account.
# Proving the new inbox keeps the account verified (User#confirm_pending_email!), so its next
# code sign-in leaves the password, passkeys and 2FA alone.
class EmailChangesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_pending_email, except: :destroy

  # GET /security/email
  def show
    render 'devise/registrations/email_change'
  end

  # POST /security/email
  def update
    unless EmailCode.confirm_new_email(current_user, params[:code])
      flash[:alert] = "That code didn't work. Send a new one and try again."
      return redirect_to(email_change_path)
    end

    old_email = current_user.email
    if current_user.confirm_pending_email!
      UserMailer.email_changed(current_user, old_email).deliver_later
      bypass_sign_in current_user
      redirect_to security_path, notice: "Your email is now #{current_user.email}."
    else
      # Taken by another account since the code went out.
      message = current_user.errors.full_messages.to_sentence.presence || "That email can't be used."
      current_user.reload.cancel_pending_email!
      redirect_to security_path, alert: message
    end
  end

  # POST /security/email/resend
  def resend
    case EmailCode.send_new_email_code(current_user)
    when :ok then flash[:notice] = "We emailed a new code to #{current_user.pending_email}."
    when :too_soon then flash[:alert] = 'We just sent a code. Give it a minute to arrive.'
    else flash[:alert] = 'Too many codes. Try again in an hour.'
    end
    redirect_to email_change_path
  end

  # DELETE /security/email
  def destroy
    current_user.cancel_pending_email!
    redirect_to security_path, notice: "Your email is still #{current_user.email}."
  end

  private

  def require_pending_email
    redirect_to security_path if current_user.pending_email.blank?
  end
end
