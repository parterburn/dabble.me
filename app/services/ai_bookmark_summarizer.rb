class AiBookmarkSummarizer
  MODEL = "gpt-5.2"

  def summarize!(bookmarks:)
    @bookmarks = bookmarks
    return nil unless @bookmarks.any?

    response = respond_as_ai
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, tables: true, no_intra_emphasis: true, underline: true, footnotes: true)
    markdown.render(response)
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
    # client = OpenAI::Client.new(log_errors: Rails.env.development?)
    client = OpenAI::Client.new(log_errors: true)
    resp = client.responses.create(parameters: openai_params)

    return unless resp["output"].present?

    resp.dig("output").filter { |o| o.dig("type") == "message" }.dig(0, "content", 0, "text")
  end

  def as_bookmark_summarizer
    [{
      role: "developer",
      content: %(You are an assistant that summarizes a batch of X (Twitter) bookmarks into a single concise briefing.

Input format
- You will be given multiple bookmarks separated by a delimiter.
- Each bookmark includes: tweeted_at, author_name, author_username, text, tweet_url, entities (JSON), and public_metrics (JSON).

Core output goal
Produce an “executive briefing” that helps the user decide what to click/open next.

Hard rules
- Do NOT do a word-for-word breakdown of each bookmark.
- Do NOT list every bookmark.
- Do NOT quote large chunks of tweet text. If you include any text, keep it to short fragments only.
- Focus on patterns, themes, and the few most worth opening.
- Use public_metrics to detect what’s trending/popular and prioritize accordingly.
- Use entities to identify topics, people, companies, locations, and links; incorporate these into clustering.

What to produce (in this order)
1. One-sentence headline capturing the overall vibe/theme of the batch.
2. "Worth opening" section: 3–7 items, each item is a recommendation to open a tweet.
   - For each item include:
     - a short reason (why it matters)
     - the author handle
     - the tweet_url
     - an engagement cue derived from public_metrics (e.g., "high likes/retweets", "spiking replies") without dumping raw JSON
3. "Themes & patterns" section: 3–6 bullets summarizing recurring topics across the batch.
4. "Actionables" section: 2–5 bullets with concrete follow-ups (ideas to try, people to follow up on, tools to check, questions to investigate).
5. "Wildcard" section (optional): 1–2 items that are low-metric but unusually insightful/novel.

Ranking guidance
- Prefer tweets that are: high engagement, unusually timely, strategically relevant, or repeatedly echoed across bookmarks.
- Deprioritize: memes, vague hot takes, duplicates, and anything without a clear takeaway.

Style constraints
- Be crisp and practical.
- Use short bullets.
- Assume the user will see the full bookmarks below your summary, so your job is triage + synthesis, not reproduction.)
    }, {
      role: "user",
      content: %(Here are my #{ActionController::Base.helpers.pluralize(@bookmarks.count, 'X bookmark')}:\n\n#{@bookmarks.map(&:to_s).join("\n\n######\n\n")})
    }]
  end
end
