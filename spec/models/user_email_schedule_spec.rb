require "rails_helper"

RSpec.describe User, "email schedule values" do
  let(:user) { FactoryBot.create(:user, plan: "PRO Monthly", frequency: ["Sun"]) }

  it "keeps only known day abbreviations in frequency" do
    user.update!(frequency: ["Mon", "Funday", "<b>Wed</b>", "", "Fri"])

    expect(user.reload.frequency).to eq(%w[Mon Fri])
  end

  it "rejects a time zone that doesn't exist" do
    expect(user.update(send_timezone: "Nowhere/Never")).to be(false)
    expect(user.errors[:send_timezone]).to be_present
  end

  it "accepts Rails and IANA zone names, including the escaped ampersand from the form" do
    expect(user.update(send_timezone: "Pacific Time (US &amp; Canada)")).to be(true)
    expect(user.reload.send_timezone).to eq("Pacific Time (US & Canada)")

    expect(user.update(send_timezone: "Europe/London")).to be(true)
  end

  it "still saves other changes for a user whose stored zone predates the check" do
    user.update_column(:send_timezone, "Old/Zone")

    expect(user.update(first_name: "Sam")).to be(true)
  end
end

RSpec.describe "Settings link schedule update", type: :request do
  let(:user) do
    FactoryBot.create(:user, plan: "PRO Monthly", frequency: ["Sun"], sign_in_count: 1,
                             send_timezone: "Mountain Time (US & Canada)")
  end

  it "ignores unknown days and zones sent through the settings link" do
    put "/unsubscribe", params: {
      token: user.email_settings_token,
      user: { frequency: ["Sun", "<i>x</i>"], send_timezone: "<i>x</i>",
              "send_time(1i)" => "2000", "send_time(2i)" => "1", "send_time(3i)" => "1",
              "send_time(4i)" => "08", "send_time(5i)" => "00" }
    }

    user.reload
    expect(user.frequency).to eq(["Sun"])
    expect(user.send_timezone).to eq("Mountain Time (US & Canada)")
  end

  it "escapes the schedule shown in the first-week navbar hint" do
    user.entries.create!(date: Date.yesterday, body: "<p>hello</p>")
    user.update_columns(frequency: ["Sun", "<i>x</i>"])
    sign_in user

    get "/entries"

    hint = response.body[/rel="popover_settings"[^>]*data-content="([^"]*)"/, 1]
    expect(hint).to be_present
    expect(CGI.unescapeHTML(hint)).to include("&lt;i&gt;x&lt;/i&gt;")
    expect(CGI.unescapeHTML(hint)).not_to include("<i>x</i>")
  end
end
