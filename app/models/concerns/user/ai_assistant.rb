class User
  module AiAssistant
    OPENAI_MODEL = "gpt-3.5-turbo".freeze
    OPENAI_TEMPERATURE = 0.85 # 0-1.0, higher = more creative
    MAX_RESPONSE_TOKENS = 200

    def ai_review(entries)
      messages = as_data_analyst
      messages += entry_bodies(entries)
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

    def as_data_analyst
      [{
        role: "system",
        content: %(You are an expert data analyst.
Using this list of feelings: Accepting, Open, Calm, Centered, Content, Fulfilled, Patient, Peaceful, Present, Relaxed, Serene, Trusting, Aliveness, Joy, Amazed, Awe, Bliss, Delighted, Eager, Ecstatic, Enchanted, Energized, Engaged, Enthusiastic, Excited, Free, Happy, Inspired, Invigorated, Lively, Passionate, Playful, Radiant, Refreshed, Rejuvenated, Renewed, Satisfied, Thrilled, Vibrant, Angry, Annoyed, Agitated, Aggravated, Bitter, Contempt, Cynical, Disdain, Disgruntled, Disturbed, Edgy, Exasperated, Frustrated, Furious, Grouchy, Hostile, Impatient, Irritated, Irate, Moody, On edge, Outraged, Pissed, Resentful, Upset, Vindictive, Courageous, Powerful, Adventurous, Brave, Capable, Confident, Daring, Determined, Free, Grounded, Proud, Strong, Worthy, Valiant, Connected, Loving, Accepting, Affectionate, Caring, Compassion, Empathy, Fulfilled, Present, Safe, Warm, Worthy, Curious, Engaged, Exploring, Fascinated, Interested, Intrigued, Involved, Stimulated, Despair, Sad, Anguish, Depressed, Despondent, Disappointed, Discouraged, Forlorn, Gloomy, Grief, Heartbroken, Hopeless, Lonely, Longing, Melancholy, Sorrow, Teary, Unhappy, Upset, Weary, Yearning, Disconnected, Numb, Aloof, Bored, Confused, Distant, Empty, Indifferent, Isolated, Lethargic, Listless, Removed, Resistant, Shut Down, Uneasy, Withdrawn, Embarrassed, Shame, Ashamed, Humiliated, Inhibited, Mortified, Self-conscious, Useless, Weak, Worthless, Fear, Afraid, Anxious, Apprehensive, Frightened, Hesitant, Nervous, Panic, Paralyzed, Scared, Terrified, Worried, Fragile, Helpless, Sensitive, Grateful, Appreciative, Blessed, Delighted, Fortunate, Grace, Humbled, Lucky, Moved, Thankful, Touched, Guilt, Regret, Remorseful, Sorry, Hopeful, Encouraged, Expectant, Optimistic, Trusting, Powerless, Impotent, Incapable, Resigned, Trapped, Victim, Tender, Calm, Caring, Loving, Reflective, Self-loving, Serene, Vulnerable, Warm, Stressed, Tense, Anxious, Burned out, Cranky, Depleted, Edgy, Exhausted, Frazzled, Overwhelm, Rattled, Rejecting, Restless, Shaken, Tight, Weary, Worn out, Unsettled, Doubt, Apprehensive, Concerned, Dissatisfied, Disturbed, Grouchy, Hesitant, Inhibited, Perplexed, Questioning, Rejecting, Reluctant, Shocked, Skeptical, Suspicious, Ungrounded, Unsure, Worried
Choose one to feeling from the list above that best represents how the user was most likely feeling when experiencing the events described in the following #{entries.size} journal entries (do not mistake feelings of others that might be described in the journal entries).
Generate a summary of these feelings, sorted by the # of entries associated to each feeling in descending order.
        )
      }]
    end

    def entry_bodies(entries)
      entry_token_count = as_data_analyst.to_s.length
      entries.each do |entry|
        body = entry.text_bodies_for_ai.first
        entry_token_count += body.length.to_f / 4
        tokens_left = max_tokens - entry_token_count - MAX_RESPONSE_TOKENS
        break if tokens_left <= 0
        {
          role: "user",
          content: Nokogiri::HTML.parse(ReverseMarkdown.convert(body, unknown_tags: :bypass)).text.first(tokens_left)
        }
      end
    end
  end
end
