# frozen_string_literal: true

module Api
  module V1
    # An emailed code that stands in for the password on an account that has none (made by email
    # code, EmailSignIn): Delete Account (AccountDeletionsController) and adding a passkey
    # (PasskeysController) take it as email_code. The web's is ::ConfirmationCodesController.
    class ConfirmationCodesController < BaseController
      # POST /api/v1/confirmation_code
      def create
        case EmailCode.send_confirmation(current_user)
        when :ok
          render json: { email: current_user.email, expires_in: EmailCode::LIFETIME.to_i,
                         resend_after: EmailCode::RESEND_AFTER.to_i }, status: :accepted
        when :too_soon
          render_error(:too_many_requests, 'too_soon', 'We just sent a code. Wait a moment before asking for another.')
        else
          render_error(:too_many_requests, 'too_many_codes', 'Too many codes. Try again in an hour.')
        end
      end
    end
  end
end
