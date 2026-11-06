# frozen_string_literal: true

require "rails_helper"

# devise-otp 2.x moved trusted-browser actions to their own controller and routes.
# These cover the app's overridden otp_tokens views against those routes.
RSpec.describe "OTP trusted browsers", type: :request do
  let(:user) { create(:user) }

  before do
    user.generate_otp_secret
    user.update!(otp_enabled: true, otp_enabled_on: 1.day.ago)
    sign_in user
  end

  it "renders trusted-browser controls that point at the persistence routes" do
    get user_otp_token_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("browser_not_trusted", scope: "devise.otp.trusted_browsers"))
    expect(response.body).to include(%(action="#{user_otp_persistence_path}"))
    expect(response.body).to include(%(action="#{reset_user_otp_persistence_path}"))
  end

  it "trusts, untrusts, and resets the current browser" do
    post user_otp_persistence_path
    expect(response).to redirect_to(user_otp_token_path)
    follow_redirect!
    expect(response.body).to include(I18n.t("browser_trusted", scope: "devise.otp.trusted_browsers"))

    delete user_otp_persistence_path
    follow_redirect!
    expect(response.body).to include(I18n.t("browser_not_trusted", scope: "devise.otp.trusted_browsers"))

    post user_otp_persistence_path
    seed_before_reset = user.reload.otp_persistence_seed

    delete reset_user_otp_persistence_path
    expect(flash[:notice]).to eq(I18n.t("successfully_reset_persistence", scope: "devise.otp.otp_persistence"))
    expect(user.reload.otp_persistence_seed).not_to eq(seed_before_reset)
    follow_redirect!
    expect(response.body).to include(I18n.t("browser_not_trusted", scope: "devise.otp.trusted_browsers"))
  end
end
