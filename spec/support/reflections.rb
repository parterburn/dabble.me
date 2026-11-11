# frozen_string_literal: true

# AI reflections (Entry::AiAssistant) are off unless a model and an Anthropic
# key are set. `include_context "reflections configured"` turns them on for a
# spec; `stub_claude` answers the request the way Anthropic's Messages API does.
module ReflectionHelpers
  CLAUDE_MESSAGES_URL = "https://api.anthropic.com/v1/messages"

  def stub_claude(text, status: 200)
    stub_request(:post, CLAUDE_MESSAGES_URL).to_return(
      status: status,
      headers: { "Content-Type" => "application/json" },
      body: {
        id: "msg_test", type: "message", role: "assistant", model: ENV["REFLECTION_MODEL"],
        content: [{ type: "text", text: text }],
        stop_reason: "end_turn", stop_sequence: nil,
        usage: { input_tokens: 100, output_tokens: 20 }
      }.to_json
    )
  end

  # The JSON body of the one request sent to Claude.
  def claude_request_body
    body = nil
    expect(WebMock).to(have_requested(:post, CLAUDE_MESSAGES_URL).with { |req| body = JSON.parse(req.body) })
    body
  end

  # Text of each message sent, whether its content is a string or blocks.
  def claude_message_texts(body)
    body["messages"].map do |message|
      content = message["content"]
      content.is_a?(String) ? content : content.select { |block| block["type"] == "text" }.map { |block| block["text"] }.join
    end
  end
end

RSpec.shared_context "reflections configured" do
  around do |example|
    previous_model = ENV["REFLECTION_MODEL"]
    previous_key = RubyLLM.config.anthropic_api_key
    ENV["REFLECTION_MODEL"] = "claude-opus-5-5"
    RubyLLM.config.anthropic_api_key = "test-anthropic-key"
    example.run
  ensure
    ENV["REFLECTION_MODEL"] = previous_model
    RubyLLM.config.anthropic_api_key = previous_key
  end
end

RSpec.configure do |config|
  config.include ReflectionHelpers
end
