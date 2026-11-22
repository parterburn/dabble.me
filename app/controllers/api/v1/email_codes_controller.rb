# frozen_string_literal: true

module Api
  module V1
    # Passwordless sign-in and sign-up for the iOS app (EmailSignIn): the app sends an email,
    # then the code from the email. The first answer is the same for every address, with an
    # account or without; the second makes the account when there wasn't one. An account with
    # 2FA also sends its authenticator code, as with a password (SessionsController).
    class EmailCodesController < BaseController
      skip_before_action :authorize_app_token!, :ensure_account_active

      # POST /api/v1/session/code {email}
      def create
        case EmailSignIn.send_code(params[:email])
        when :invalid_email
          render_error(:unprocessable_entity, 'invalid_email', 'Enter a valid email address.')
        when :too_soon
          render_error(:too_many_requests, 'too_soon', 'We just sent a code. Wait a moment before asking for another.')
        when :too_many
          render_error(:too_many_requests, 'too_many_codes', 'Too many codes for this email. Try again in an hour.')
        else
          render json: { email: EmailSignIn.normalize(params[:email]), expires_in: EmailCode::LIFETIME.to_i,
                         resend_after: EmailCode::RESEND_AFTER.to_i, code_length: EmailCode::LENGTH },
                 status: :accepted
        end
      end

      # POST /api/v1/session/code/verify {email, code, otp_code?}
      def verify
        email = EmailSignIn.normalize(params[:email])
        email_code = EmailSignIn.match(email, params[:code])
        return invalid_code unless email_code

        user = EmailSignIn.account_for(email)
        if user
          return render_error(:unauthorized, 'invalid_code', invalid_code_message) unless user.active_for_authentication?
          return if otp_failed?(user)
        end

        result = EmailSignIn.complete!(email_code, email) { |new_user| EmailSignIn.set_platform(new_user, 'ios_app') }
        case result
        when nil then invalid_code
        when :signups_closed
          render_error(:forbidden, 'signups_closed', 'Dabble Me is closing and no longer takes new accounts.')
        when :invalid
          render_error(:unprocessable_entity, 'invalid_account', "Couldn't make an account for that email. Try again.")
        else
          signed_in(result)
        end
      end

      private

      def signed_in(result)
        user = result.user
        deletion_cancelled = user.cancel_pending_deletion!
        user.update_tracked_fields!(request)
        token = MobileApp.issue_token!(user)
        # created: a new account. The app asks to add a passkey after a sign-in, not a sign-up.
        render json: MobileApp.token_response(token)
                              .merge(created: result.created, deletion_cancelled: deletion_cancelled,
                                     **MobileApp.passkey_setup(user, token)),
               status: result.created ? :created : :ok
      end

      # Renders the answer and returns true when the account has 2FA and its code is missing or
      # wrong. The emailed code isn't used up, so the app sends it again with the 2FA code.
      def otp_failed?(user)
        return false unless user.otp_enabled?

        otp = params[:otp_code].to_s.gsub(/\s/, '')
        if otp.blank?
          render_error(:unauthorized, 'otp_required', 'Enter the 6-digit code from your authenticator app.')
        elsif !user.validate_otp_or_recovery_token(otp)
          render_error(:unauthorized, 'invalid_otp', "That code didn't work. Try the newest one, or a recovery code.")
        else
          return false
        end
        true
      end

      def invalid_code
        render_error(:unauthorized, 'invalid_code', invalid_code_message)
      end

      def invalid_code_message
        "That code didn't work. Check the newest email from Dabble Me, or send a new code."
      end
    end
  end
end
