# frozen_string_literal: true

module Api
  module V1
    # Native sign-up for the iOS app. The web form's Turnstile captcha has no native
    # counterpart, so Rack::Attack's sign-up limits (per IP and per email) carry that load.
    class RegistrationsController < BaseController
      skip_before_action :authorize_app_token!, :ensure_account_active

      # POST /api/v1/registration {email, password, first_name?, platform?}
      # `platform` is which app is signing up (User::APP_SIGNUP_PLATFORMS). The iOS app doesn't
      # send it, so anything else counts as "ios_app"; an Android app would send "android_app".
      def create
        # No new accounts once a closing is announced (ApplicationController#refuse_when_closing).
        if SiteClosure.current
          return render_error(:forbidden, 'signups_closed', 'Dabble Me is closing and no longer takes new accounts.')
        end

        password = params[:password].to_s
        user = User.new(
          email: params[:email].to_s.strip.downcase,
          password: password,
          password_confirmation: password,
          first_name: params[:first_name].to_s.strip.presence,
          signup_platform: app_signup_platform
        )
        unless user.save
          return render_error(:unprocessable_entity, 'invalid_account', user.errors.full_messages.first,
                              details: user.errors.full_messages)
        end

        user.update_tracked_fields!(request)
        token = MobileApp.issue_token!(user)
        render json: MobileApp.token_response(token).merge(MobileApp.passkey_setup(user, token)), status: :created
      end

      private

      def app_signup_platform
        platform = params[:platform].to_s
        User::APP_SIGNUP_PLATFORMS.include?(platform) ? platform : 'ios_app'
      end
    end
  end
end
