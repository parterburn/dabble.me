class AiBookmarkSummarizer
  MODEL = "gpt-5.2"

  def summarize(user, since: nil)
    return nil unless since.present? && user.x_bookmarks.where(created_at: since..).any?

    @user = user
    @since = since
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
      content: %(Summarize the following X bookmarks into a concise, actionable summary.)
    }, {
      role: "user",
      content: %(Here are the X bookmarks to summarize: #{@user.x_bookmarks.where(created_at: @since..).map(&:to_s).join("\n\n######\n\n")})
    }]
  end
end
