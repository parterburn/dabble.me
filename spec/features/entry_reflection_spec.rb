# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Reflecting on an entry", type: :feature, js: true do
  include_context "has all objects"

  let!(:ai_entry) { FactoryBot.create(:entry, user: paid_user_ai, date: Date.new(2026, 6, 10), body: "<p>Long walk by the river.</p>") }

  before do
    stub_request(:post, "https://api.openai.com/v1/responses").to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { output: [{ type: "message", content: [{ type: "output_text", text: "Sounds restful.\n\n**What did you notice?**" }] }] }.to_json
    )
    sign_in paid_user_ai
  end

  it "explains the feature and sends nothing to OpenAI until Generate Reflection is pressed" do
    visit day_entry_path(year: 2026, month: 6, day: 10)
    find(".j-reflect").click

    within("dialog.s-reflection-dialog[open]") do
      expect(page).to have_content("sends this entry to OpenAI")
      expect(page).to have_button("Generate Reflection")
      expect(page).to have_no_css(".s-reflection-note")
      find(".close").click
    end

    expect(page).to have_no_css("dialog.s-reflection-dialog[open]")
    expect(a_request(:post, "https://api.openai.com/v1/responses")).not_to have_been_made
  end

  it "shows the reflection in a dialog and saves nothing" do
    visit day_entry_path(year: 2026, month: 6, day: 10)
    find(".j-reflect").click

    within("dialog.s-reflection-dialog[open]") do
      expect(page).to have_css(".s-reflection-date", text: /Wednesday, Jun 10, 2026/i) # uppercased by CSS
      click_button "Generate Reflection"
      expect(page).to have_css("strong", text: "What did you notice?")
      expect(page).to have_css(".s-reflection-note", text: "Written by AI from this entry")
      find(".close").click
    end

    expect(page).to have_no_css("dialog.s-reflection-dialog[open]")
    expect(ai_entry.reload.body).to eq("<p>Long walk by the river.</p>")
  end
end
