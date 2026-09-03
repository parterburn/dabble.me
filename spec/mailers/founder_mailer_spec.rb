require "rails_helper"

RSpec.describe FounderMailer do
  include ActiveSupport::Testing::TimeHelpers

  it "sends a short weekly summary to admins" do
    create(:user, admin: true, email: "owner@example.com")
    dashboard = Admin::Dashboard.new

    email = described_class.weekly_digest(["owner@example.com"], dashboard)

    expect(email.to).to eq(["owner@example.com"])
    expect(email.subject).to include("ARR")
    expect(email.body.encoded).to include("Needs attention")
    expect(email.body.encoded).to include("/admin/stats")
    expect(email.body.encoded).to include("MCP")
  end
end
