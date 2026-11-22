require "rails_helper"

# users.signup_platform: where an account was made, for Admin Stats and the welcome email.
RSpec.describe "Recording where an account signed up", type: :request do
  let(:password) { "a long password" }

  before { MobileApp.ensure_application! }

  it "records a web sign-up as web, whatever the form posts" do
    post user_registration_path, params: {
      user: { email: "web@example.com", password: password, password_confirmation: password, signup_platform: "ios_app" }
    }

    expect(User.find_by(email: "web@example.com").signup_platform).to eq("web")
  end

  it "records the app's native sign-up as ios_app" do
    post "/api/v1/registration", params: { email: "app@example.com", password: password }, as: :json

    expect(response).to have_http_status(:created)
    expect(User.find_by(email: "app@example.com").signup_platform).to eq("ios_app")
  end

  it "takes another app's platform when it names one, and ignores anything else" do
    post "/api/v1/registration", params: { email: "droid@example.com", password: password, platform: "android_app" }, as: :json
    post "/api/v1/registration", params: { email: "odd@example.com", password: password, platform: "web" }, as: :json

    expect(User.find_by(email: "droid@example.com").signup_platform).to eq("android_app")
    expect(User.find_by(email: "odd@example.com").signup_platform).to eq("ios_app")
  end

  it "leaves accounts made any other way unknown, and refuses a platform it doesn't know" do
    user = create(:user)

    expect(user.signup_platform).to be_nil
    expect(user.signed_up_in_app?).to be(false)
    expect(build(:user, signup_platform: "fax")).not_to be_valid
  end
end
