# frozen_string_literal: true

module Api
  # JSON shape for /api/v1 entries (iOS app). Bodies are sent as text (light Markdown
  # from Entry#text_body) so the client never has to render stored HTML.
  class EntrySerializer
    EXCERPT_LENGTH = 280

    def self.summary(entry)
      new(entry).summary
    end

    def self.full(entry)
      new(entry).full
    end

    def initialize(entry)
      @entry = entry
    end

    def summary
      {
        id: entry.id,
        date: entry.date.to_date.iso8601,
        excerpt: entry.text_body.to_s.squish.truncate(EXCERPT_LENGTH, separator: ' '),
        image_url: entry.display_image_url,
        image_processing: entry.uploading_image?,
        hashtags: entry.hashtags || [],
        updated_at: entry.updated_at.iso8601
      }
    end

    def full
      summary.merge(
        body_text: display_text(entry.text_body),
        # Structured, editable copy of the body (see EntryDocument), or nil when it's web-only.
        document: EntryDocument.from_html(entry.body),
        songs: songs,
        web_url: Mcp::Tools::Helpers.entry_public_url(entry)
      )
    end

    private

    attr_reader :entry

    # Entry#text_body is Markdown from ReverseMarkdown, which turns email blank lines
    # (<div><br></div>) into "  \n\n" sequences. Trim line ends and collapse blank-line runs
    # so the app shows one blank line between paragraphs, like the web.
    def display_text(text)
      text.to_s.gsub(/[ \t]+$/, '').gsub(/\n{3,}/, "\n\n").strip
    end

    def songs
      Array(entry.songs).filter_map do |song|
        next if song['spotify_id'].blank?

        {
          title: song['title'],
          artists: Array(song['artists']),
          spotify_url: "https://open.spotify.com/track/#{song['spotify_id']}"
        }
      end
    end
  end
end
