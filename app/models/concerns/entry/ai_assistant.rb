class Entry
  module AiAssistant
    OPENAI_MODEL = "gpt-3.5-turbo".freeze
    OPENAI_TEMPERATURE = 0.85 # 0-1.0, higher = more creative
    MAX_RESPONSE_TOKENS = 500

    def ai_response
      messages = as_therapist
      messages += entry_body
      respond_as_ai(messages)
    end

    private

    def max_tokens
      if OPENAI_MODEL == "gpt-4"
        8000
      else
        4000
      end
    end

    def respond_as_ai(messages)
      client = OpenAI::Client.new
      resp = client.chat(
        parameters: {
          model: OPENAI_MODEL,
          messages: messages,
          temperature: OPENAI_TEMPERATURE,
          max_tokens: MAX_RESPONSE_TOKENS
        }
      )
      if resp["choices"].present?
        resp.dig("choices", 0, "message", "content")
      else
        p resp.dig("error", "type")
        p resp.dig("error", "message")
      end
    end

    def as_therapist
      [{
        role: "system",
        content: %(You are an expertly-trained psycho-therapist. Respond to a journal entry as the therapist with a light and witty analysis. If the sentiment of tne user's journal entry is positive, be humorous and extra creative in your response.
On your initial response, ask follow up questions that will help the user dig into their experience or feelings more.
On your second response close out the conversation by celebrating the user for taking the time to journal with a positive and inspiring personal growth-focused message.
During all of your responses, list out any resources that you can provide that may be relevant to your analysis and provide the user with links to those resources that you think would be helpful.
        )
      },
      {
        role: "user",
        content: %(Leave blank lines in between your response, and your follow-up questions.

Your first response should follow this example format:
```
Sounds like you had a [day](https://www.resource-link.com) filled with...

What was your favorite part of the day?
```

Subsequent responses should use the following example format. Do not ask any follow-up questions in your subsequent responses. Close out the conversation by celebrating the user for taking the time to journal with a positive and inspiring personal growth-focused message. Be more serious, do not respond in haiku/song/joke/etc.
```
It's understandable to feel...Here's a resource that might help you...

Great job showing up today... It's always wonderful...
```
        )
      }]
    end

    def entry_body
      entry_token_count = as_therapist.to_s.length
      text_bodies_for_ai.map do |body|
        entry_token_count += body.length.to_f / 4
        tokens_left = max_tokens - entry_token_count - MAX_RESPONSE_TOKENS
        role = body.starts_with?("||DabbleMeGPT||") ? "assistant" : "user"
        {
          role: role,
          content: Nokogiri::HTML.parse(ReverseMarkdown.convert(body.gsub("||DabbleMeGPT||", ""), unknown_tags: :bypass)).text.first(tokens_left)
        }
      end.compact
    end
  end
end
