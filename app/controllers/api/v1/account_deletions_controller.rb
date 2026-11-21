# frozen_string_literal: true

module Api
  module V1
    # Settings → Delete Account, in the app. The same as the web's delete page
    # (RegistrationsController#destroy): confirmed with the password, and the account goes an
    # hour later (DeleteUserJob, which cancels a Stripe subscription), unless the person
    # signs back in before then.
    class AccountDeletionsController < BaseController
      include PasskeyAssertion

      # GET /api/v1/account_deletion: what the confirmation says.
      def show
        render json: {
          entry_count: current_user.entries.count,
          # Billing the deletion can't stop (Gumroad, PayPal, or Stripe with no customer on file).
          separate_billing: current_user.separate_billing_to_cancel,
          # Read by builds before 110 only; newer ones email the export (POST /api/v1/exports).
          export_url: "#{ApplicationHelper.site_public_base_url}/entries/export"
        }
      end

      # POST /api/v1/account_deletion {password}, or {challenge_token, credential}: one of the
      # account's own passkeys (challenge from GET /api/v1/session/passkey), for someone who
      # signs in with a passkey and may not know the password.
      def create
        if params[:credential].present?
          unless passkey_user == current_user
            return render_error(:forbidden, 'passkey_failed', "That passkey didn't confirm it. Try again, or use your password.")
          end
        elsif !current_user.valid_password?(params[:password].to_s)
          return render_error(:forbidden, 'incorrect_password', 'Incorrect password.')
        end

        current_user.update_column(:deleted_at, Time.current)
        DeleteUserJob.set(wait: 1.hour).perform_later(current_user.id, current_user.deleted_at.to_i)
        # Signed out, as the web signs out: this token and its refresh token stop working now.
        doorkeeper_token.revoke
        render json: { deletes_at: (current_user.deleted_at + 1.hour).iso8601 }
      end
    end
  end
end
