# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Asking for a passkey on the web (PasskeyNudge)", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "asks on Today, linking to Account Security's passkeys" do
    get today_path
    expect(response.body).to include('id="passkey-nudge"')
    expect(response.body).to include("#{security_path}#passkeys")
  end

  it "doesn't ask once the account has a passkey" do
    register_passkey(user)
    get today_path
    expect(response.body).not_to include('id="passkey-nudge"')
  end

  it "doesn't ask on other pages" do
    get security_path
    expect(response.body).not_to include('id="passkey-nudge"')
  end

  it "stays quiet while put off, and asks again after" do
    cookies[PasskeyNudge.cookie_name(user)] = "1:#{1.day.from_now.to_i}"
    get today_path
    expect(response.body).not_to include('id="passkey-nudge"')

    cookies[PasskeyNudge.cookie_name(user)] = "1:#{1.day.ago.to_i}"
    get today_path
    expect(response.body).to include('id="passkey-nudge"')
  end

  it "keeps one account's Not now to that account" do
    cookies[PasskeyNudge.cookie_name(create(:user))] = "1:#{1.day.from_now.to_i}"
    get today_path
    expect(response.body).to include('id="passkey-nudge"')
  end

  it "stops after the last Not now" do
    cookies[PasskeyNudge.cookie_name(user)] = "#{PasskeyNudge::MAX_ASKS}:#{1.day.ago.to_i}"
    get today_path
    expect(response.body).not_to include('id="passkey-nudge"')
  end
end
