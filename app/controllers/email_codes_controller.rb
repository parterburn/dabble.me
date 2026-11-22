# Passwordless sign-in and sign-up on the web (EmailSignIn). The Log in and Sign up pages ask
# only for an email (or offer a passkey); Continue always emails a code and shows the code page,
# with or without an account at that address, so neither page says which emails are on Dabble
# Me. The code page shows where the code went ("Wrong email? Change it"), can send it again, and
# has "Use password instead" for accounts that have one (Devise's own sign-in, which fails the
# same way for an unknown address).
#
# The address being signed in waits in the session (EMAIL_CODE_SESSION) between the pages.
class EmailCodesController < ApplicationController
  layout 'marketing'

  EMAIL_CODE_SESSION = :email_code_sign_in
  # After signing in with a code, adding a passkey on Account Security needs nothing more for
  # this long (Passkeys::RegistrationsController), as the app's setup token does.
  SIGNED_IN_SESSION = :email_code_signed_in_at
  FRESH_FOR = 15.minutes

  before_action :redirect_signed_in, only: %i[create show verify resend]
  before_action :require_pending_email, only: %i[show verify resend]

  # POST /users/sign_in/code {email, remember_me, gift_code}
  def create
    email = EmailSignIn.normalize(params.dig(:user, :email).presence || params[:email])
    intent = params[:intent] == 'sign_up' ? 'sign_up' : 'sign_in'
    status = EmailSignIn.send_code(email)

    if status == :invalid_email
      redirect_to back_to_form(intent, email, params[:gift_code]), alert: 'Enter a valid email address.'
      return
    end
    if status == :too_many
      redirect_to back_to_form(intent, email, params[:gift_code]), alert: 'Too many codes for that email. Try again in an hour.'
      return
    end

    session[EMAIL_CODE_SESSION] = {
      'email' => email,
      'intent' => intent,
      'remember_me' => ActiveModel::Type::Boolean.new.cast(params.dig(:user, :remember_me) || params[:remember_me]) || false,
      'gift_code' => params[:gift_code].presence
    }.compact
    # :too_soon: a code went out moments ago, so the code page is still the right place.
    redirect_to email_code_path
  end

  # GET /users/sign_in/code
  def show
    render 'devise/sessions/code'
  end

  # POST /users/sign_in/code/resend
  def resend
    case EmailSignIn.send_code(pending['email'])
    when :sent then flash[:notice] = "We sent a new code to #{pending['email']}."
    when :too_soon then flash[:alert] = 'We just sent a code. Give it a minute to arrive before asking for another.'
    else flash[:alert] = 'Too many codes for this email. Try again in an hour.'
    end
    redirect_to email_code_path
  end

  # POST /users/sign_in/code/verify {code}
  def verify
    email = pending['email']
    email_code = EmailSignIn.match(email, params[:code])
    return wrong_code unless email_code

    user = EmailSignIn.account_for(email)
    return wrong_code if user && !user.active_for_authentication?

    result = EmailSignIn.complete!(email_code, email, referrer: request.env['affiliate.tag']) do |new_user|
      EmailSignIn.set_platform(new_user, 'web')
      new_user.welcome_email_after_gift = true if current_gift
    end
    case result
    when nil then return wrong_code
    when :signups_closed then return redirect_to(goodbye_path)
    when :invalid
      session.delete(EMAIL_CODE_SESSION)
      return redirect_to(new_user_registration_path, alert: "Couldn't make an account for that email. Try again.")
    end

    session.delete(EMAIL_CODE_SESSION)
    finish_sign_in(result.user, created: result.created, remember: pending['remember_me'])
  end

  private

  def finish_sign_in(user, created:, remember:)
    # 2FA: the authenticator code still comes after the emailed one, on devise-otp's page, as
    # after a password.
    if user.otp_enabled?
      challenge = user.generate_otp_challenge!
      redirect_to user_otp_credential_path(challenge: challenge, remember_me: remember)
      return
    end

    user.remember_me = remember
    sign_in(:user, user)
    session[SIGNED_IN_SESSION] = Time.current.to_i

    if created
      redirect_to after_sign_in_path_for(user), **sign_up_flash(user)
    elsif current_gift
      # An existing account with a gift link: the gift page has the redeem button.
      redirect_to gift_path(current_gift.code)
    else
      redirect_to after_sign_in_path_for(user)
    end
  end

  def sign_up_flash(user)
    if current_gift
      if current_gift.redeem!(user)
        UserMailer.welcome_email(user).deliver_later
        return { notice: "Welcome to Dabble Me! Your gift of PRO runs until #{user.gift_expires_on}." }
      end
      UserMailer.welcome_email(user).deliver_later
      return { alert: 'That gift code is no longer valid, so your account is on the Free plan.' }
    end
    { notice: 'Welcome to Dabble Me! Your account is ready.' }
  end

  def wrong_code
    flash.now[:alert] = "That code didn't work. Check the newest email from Dabble Me, or send a new code."
    render 'devise/sessions/code', status: :unprocessable_content
  end

  def current_gift
    return @current_gift if defined?(@current_gift)

    @current_gift = (pending && pending['gift_code']) ? Gift.find(pending['gift_code']) : nil
  end
  helper_method :current_gift

  def pending
    @pending ||= session[EMAIL_CODE_SESSION].presence
  end
  helper_method :pending

  def require_pending_email
    redirect_to new_user_session_path unless pending && pending['email'].present?
  end

  def redirect_signed_in
    redirect_to root_path if user_signed_in?
  end

  def back_to_form(intent, email, gift_code)
    if gift_code.present?
      gift_path(gift_code, email: email)
    elsif intent == 'sign_up'
      new_user_registration_path(email: email)
    else
      new_user_session_path(email: email)
    end
  end
end
