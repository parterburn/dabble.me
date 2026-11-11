require "rails_helper"

RSpec.describe Entry::AiAssistant do
  include_context "reflections configured"

  let(:user) { FactoryBot.create(:user, plan: "PRO Monthly PayHere", payhere_id: 1, first_name: "Sam", ai_opt_in: true) }
  let(:entry) { FactoryBot.create(:entry, user: user, date: Date.new(2026, 6, 10), body: "<p>Long run by the river. #running</p>") }

  before { stub_claude("**How did it feel?**") }

  it "renders the reply as HTML" do
    expect(entry.ai_reflection).to include("<strong>How did it feel?</strong>")
  end

  it "asks the model named in REFLECTION_MODEL, at low effort, with the life coach instructions" do
    entry.ai_reflection
    body = claude_request_body

    expect(body["model"]).to eq("claude-opus-5-5")
    expect(body["output_config"]).to eq("effort" => "low")
    expect(body["max_tokens"]).to eq(Entry::AiAssistant::MAX_OUTPUT_TOKENS)
    expect(body).not_to include("temperature", "tools", "thinking")
    system = Array(body["system"]).map { |block| block.is_a?(Hash) ? block["text"] : block }.join
    expect(system).to include("journaling assistant")
    expect(system).not_to match(/hashtag/i)
  end

  it "asks for a refusal fallback on models that support one, and not on others" do
    entry.ai_reflection
    expect(claude_request_body["fallbacks"]).to eq("default")
    expect(WebMock).to have_requested(:post, ReflectionHelpers::CLAUDE_MESSAGES_URL)
      .with(headers: { "anthropic-beta" => Entry::AiAssistant::REFUSAL_FALLBACK_BETA, "x-api-key" => "test-anthropic-key" })

    WebMock.reset_executed_requests!
    ENV["REFLECTION_MODEL"] = "claude-haiku-5-5"
    entry.ai_reflection
    body = claude_request_body
    expect(body["model"]).to eq("claude-haiku-5-5")
    expect(body).not_to include("fallbacks")
    expect(WebMock).not_to have_requested(:post, ReflectionHelpers::CLAUDE_MESSAGES_URL).with(headers: { "anthropic-beta" => /fallback/ })
  end

  it "adds the month before and entries sharing a hashtag as context, but not this entry or later ones" do
    FactoryBot.create(:entry, user: user, date: Date.new(2026, 6, 3), body: "<p>Rest day, sore legs.</p>")
    FactoryBot.create(:entry, user: user, date: Date.new(2025, 1, 5), body: "<p>Signed up for a 10k. #running</p>")
    FactoryBot.create(:entry, user: user, date: Date.new(2026, 7, 1), body: "<p>Later entry. #running</p>")
    FactoryBot.create(:entry, user: user, date: Date.new(2026, 1, 1), body: "<p>Unrelated winter entry.</p>")

    entry.ai_reflection
    body = claude_request_body
    texts = claude_message_texts(body)
    context = texts[0..-2].join("\n")

    expect(body["messages"].map { |message| message["role"] }.uniq).to eq(["user"])
    expect(context).to include("Rest day, sore legs.", "Signed up for a 10k.")
    expect(context).not_to include("Unrelated winter entry.", "Long run by the river.", "Later entry.")
    expect(texts.last).to include("My name is Sam.", "Wednesday, June 10, 2026", "Long run by the river.")
  end

  it "sends no context when there are no earlier or related entries" do
    entry.update!(body: "<p>Just today, no tags.</p>")
    entry.ai_reflection
    expect(claude_request_body["messages"].size).to eq(1)
  end

  it "sends the entry's photo by URL" do
    allow(entry).to receive(:image_stored?).and_return(true)
    allow(entry).to receive(:image_url_cdn).and_return("https://cdn.example.com/photo.jpg")

    entry.ai_reflection

    blocks = claude_request_body["messages"].last["content"]
    expect(blocks).to include(hash_including("type" => "image", "source" => { "type" => "url", "url" => "https://cdn.example.com/photo.jpg" }))
  end

  describe ".configured?" do
    it "needs both a model and an Anthropic key" do
      expect(described_class.configured?).to be(true)

      ENV["REFLECTION_MODEL"] = ""
      expect(described_class.configured?).to be(false)

      ENV["REFLECTION_MODEL"] = "claude-opus-5-5"
      RubyLLM.config.anthropic_api_key = nil
      expect(described_class.configured?).to be(false)
    end
  end
end
