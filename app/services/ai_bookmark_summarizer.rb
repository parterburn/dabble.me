class AiBookmarkSummarizer
  MODEL = "gpt-5.2"

  def summarize!(bookmarks:)
    @bookmarks = bookmarks
    return nil unless @bookmarks.any?

    respond_as_ai
  end

  private

  def openai_params
    params = {
      input: as_bookmark_summarizer,
      model: MODEL,
      reasoning: { effort: "medium" },
      store: false
    }

    params[:tools] = [
      {
        type: "web_search_preview",
        search_context_size: "medium"
      }
    ]
    params
  end

  def respond_as_ai
    client = OpenAI::Client.new(log_errors: Rails.env.development?)
    resp = client.responses.create(parameters: openai_params)

    return unless resp["output"].present?

    resp.dig("output").filter { |o| o.dig("type") == "message" }.dig(0, "content", 0, "text")
  end

  def as_bookmark_summarizer
    [{
      role: "developer",
      content: %(You summarize X bookmarks into a scannable HTML briefing for email.

OUTPUT FORMAT: Raw HTML only. No markdown. No code fences. Use <b>, <i>, <a>, <ul>, <li>, <p> tags.

INPUT: Bookmarks separated by "######". Each has: tweeted_at, author_name, author_username, text, tweet_url, entities (JSON), public_metrics (JSON).

HARD RULES:
- Output raw HTML directly. Do NOT wrap in markdown code blocks.
- Never output raw URLs as text. Always hyperlink them: <a href="URL">descriptive text</a>.
- Hyperlink tweet references using the tweet_url with a short descriptive title as link text.
- Each tweet may appear in ONE section only. No duplicates across sections.
- Omit any section entirely if it has no relevant items.
- Keep it highly scannable: short bullets, bold key phrases, minimal prose.
- Do NOT reproduce tweet text verbatim. Summarize in a few words.

SECTIONS (in order, all optional — skip if empty):

1. <h3>Themes</h3> — 1 to 4 short bullets identifying recurring patterns/topics across the batch. No individual tweet links here.

2. <h3>Most Engagement</h3> — Up to 5 tweets ranked by engagement (likes, retweets, bookmarks). For each:
   - <a href="tweet_url"><b>Short descriptive title</b></a> — @author_handle
   - One short line on why it's notable (do not state the obvious/generic reasons like high likes, retweets, bookmarks, replies, etc.)

3. <h3>Wildcards</h3> — 1–2 low-metric but unusually insightful/novel insights from the tweets (hyperlink to specific topics). Similar format as above.

RANKING: Prefer high engagement, timely, strategically relevant. Deprioritize memes, vague hot takes, duplicates.

STYLE: Crisp. Practical. The full bookmarks appear below the summary so your job is triage, not reproduction.)
    }, {
      role: "user",
      content: %(Here are my #{ActionController::Base.helpers.pluralize(@bookmarks.count, 'X bookmark')}:\n\n#{@bookmarks.map(&:to_s).join("\n\n######\n\n")})
    }]
  end
end
