# RubyLLM talks to Anthropic for entry reflections (Entry::AiAssistant), which
# sets its own model (REFLECTION_MODEL), timeout and retries per request.
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end
