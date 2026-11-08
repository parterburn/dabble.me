# frozen_string_literal: true

module Api
  module V1
    class AccountsController < BaseController
      RESEND_WINDOW = 10.minutes

      # POST /api/v1/account/deletion_request
      # Emails a link to the web deletion page; nothing is deleted from the app.
      def deletion_request
        cache_key = "account_deletion_request:#{current_user.id}"
        unless Rails.cache.read(cache_key)
          UserMailer.account_deletion_requested(current_user).deliver_later
          Rails.cache.write(cache_key, true, expires_in: RESEND_WINDOW)
        end

        render json: { email: current_user.email }, status: :accepted
      end
    end
  end
end
