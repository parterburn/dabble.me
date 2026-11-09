require "rails_helper"

RSpec.describe Entry::AiAssistant do
  let(:user) { FactoryBot.create(:user, plan: "PRO Monthly PayHere", payhere_id: 1, first_name: "Sam", ai_opt_in: true) }
  let(:responses_url) { "https://api.openai.com/v1/responses" }
  let(:entry) { FactoryBot.create(:entry, user: user, date: Date.new(2026, 6, 10), body: "<p>Long run by the river. #running</p>") }

  before do
    stub_request(:post, responses_url).to_return(
      status: 200,
      headers: { "Content-Type" => "application/json" },
      body: { output: [{ type: "message", content: [{ type: "output_text", text: "**How did it feel?**" }] }] }.to_json
    )
  end

  def sent_input
    input = nil
    expect(WebMock).to(have_requested(:post, responses_url).with { |req| input = JSON.parse(req.body)["input"] })
    input
  end

  it "renders the reply as HTML" do
    expect(entry.ai_reflection).to include("<strong>How did it feel?</strong>")
  end

  it "uses the life coach instructions without hashtag suggestions" do
    entry.ai_reflection
    instructions = sent_input.first
    expect(instructions["role"]).to eq("developer")
    expect(instructions["content"]).to include("journaling assistant")
    expect(instructions["content"]).not_to match(/hashtag/i)
  end

  it "adds the month before and entries sharing a hashtag as context, but not this entry or later ones" do
    FactoryBot.create(:entry, user: user, date: Date.new(2026, 6, 3), body: "<p>Rest day, sore legs.</p>")
    FactoryBot.create(:entry, user: user, date: Date.new(2025, 1, 5), body: "<p>Signed up for a 10k. #running</p>")
    FactoryBot.create(:entry, user: user, date: Date.new(2026, 7, 1), body: "<p>Later entry. #running</p>")
    FactoryBot.create(:entry, user: user, date: Date.new(2026, 1, 1), body: "<p>Unrelated winter entry.</p>")

    entry.ai_reflection
    context = sent_input[1..-2].map { |message| message["content"] }.join("\n")

    expect(context).to include("Rest day, sore legs.")
    expect(context).to include("Signed up for a 10k.")
    expect(context).not_to include("Unrelated winter entry.")
    expect(context).not_to include("Long run by the river.")
    expect(context).not_to include("Later entry.")
    expect(sent_input.last["content"]).to include("My name is Sam.", "Wednesday, June 10, 2026", "Long run by the river.")
  end

  it "sends no context when there are no earlier or related entries" do
    entry.update!(body: "<p>Just today, no tags.</p>")
    entry.ai_reflection
    expect(sent_input.size).to eq(2)
  end
end
