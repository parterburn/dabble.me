require "rails_helper"

RSpec.describe AiUsage do
  include_context "reflections configured"

  let(:user) { FactoryBot.create(:user, plan: "PRO Monthly PayHere", payhere_id: 1, ai_opt_in: true) }
  let(:entry) { FactoryBot.create(:entry, user: user, date: Date.new(2026, 6, 10), body: "<p>Long run.</p>") }

  it "logs each reflection's model, tokens and cost, and no entry text" do
    stub_claude("**How did it feel?**") # 100 input and 20 output tokens

    expect { entry.ai_reflection }.to change(user.ai_usages, :count).by(1)

    usage = user.ai_usages.last
    expect(usage).to have_attributes(model: "claude-opus-5-5", input_tokens: 100, output_tokens: 20)
    # Opus 5.5: $4 per million input tokens, $20 per million output tokens.
    expect(usage.cost_usd).to eq(BigDecimal("0.0008"))
    expect(usage.attributes.values.map(&:to_s).join).not_to include("Long run")
  end

  it "records the model that answered when Anthropic says so" do
    stub_claude("Hi")
    WebMock.stub_request(:post, ReflectionHelpers::CLAUDE_MESSAGES_URL).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: "msg", type: "message", role: "assistant", model: "claude-opus-5", content: [{ type: "text", text: "Hi" }],
              stop_reason: "end_turn", usage: { input_tokens: 10, output_tokens: 5 } }.to_json
    )

    entry.ai_reflection
    expect(user.ai_usages.last.model).to eq("claude-opus-5")
  end

  it "doesn't log a request that failed" do
    allow(Sentry).to receive(:capture_exception)
    stub_claude("", status: 500)

    expect { entry.ai_reflection rescue nil }.not_to change(described_class, :count)
  end

  it "still returns the reflection when logging fails" do
    stub_claude("**Still here?**")
    allow(described_class).to receive(:create!).and_raise(ActiveRecord::ConnectionNotEstablished)
    allow(Sentry).to receive(:capture_exception)

    expect(entry.ai_reflection).to include("<strong>Still here?</strong>")
    expect(Sentry).to have_received(:capture_exception).with(kind_of(ActiveRecord::ConnectionNotEstablished), level: :warning)
  end

  it "is deleted with its user, including DeleteUserJob's user.delete" do
    described_class.create!(user: user, model: "claude-opus-5-5", input_tokens: 1, output_tokens: 1, cost_usd: 0.01)
    Entry.where(user: user).delete_all

    expect { user.delete }.to change(described_class, :count).by(-1)
  end
end
