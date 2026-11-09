# frozen_string_literal: true

module Api
  # JSON shape for /api/v1 entries (iOS app). Bodies are sent as text (light Markdown
  # from Entry#text_body) so the client never has to render stored HTML.
  class EntrySerializer
    EXCERPT_LENGTH = 280
    PREVIEW_LENGTH = 1500

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
        excerpt: plain_excerpt,
        # The text for long-press previews (light Markdown, capped), so the app can show the whole
        # entry right away: iOS sizes a preview once, before anything could load.
        preview_text: display_text(entry.text_body).truncate(PREVIEW_LENGTH, separator: ' '),
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
        # Hashtags with a date set on dabble.me (birthdays, anniversaries), and how long it had
        # been on this entry's day, worded like the web's tag tooltip.
        dated_hashtags: dated_hashtags,
        # Neighbouring entries by date, for moving between days in the app.
        previous_entry: neighbour(entry.previous),
        next_entry: neighbour(entry.next),
        web_url: Mcp::Tools::Helpers.entry_public_url(entry)
      )
    end

    private

    attr_reader :entry

    # Visible text only: text_body is Markdown, so it would show "**bold**" markers in the
    # timeline. Block ends and line breaks become spaces so words don't run together.
    def plain_excerpt
      html = entry.formatted_body.to_s.gsub(%r{<br\s*/?>|</(?:p|div|li|h\d|blockquote)>|<hr\s*/?>}i, ' ')
      Nokogiri::HTML5.fragment(html).text.squish.truncate(EXCERPT_LENGTH, separator: ' ')
    end

    # Entry#text_body is Markdown from ReverseMarkdown, which turns email blank lines
    # (<div><br></div>) into "  \n\n" sequences. Trim line ends and collapse blank-line runs
    # so the app shows one blank line between paragraphs, like the web.
    def display_text(text)
      text.to_s.gsub(/[ \t]+$/, '').gsub(/\n{3,}/, "\n\n").strip
    end

    def neighbour(other)
      other && { id: other.id, date: other.date.to_date.iso8601 }
    end

    def dated_hashtags
      tags = entry.hashtags || []
      return [] if tags.empty?

      dates = Hashtag.where(user_id: entry.user_id).where.not(date: nil).to_h { |hashtag| [hashtag.tag.downcase, hashtag.date.to_date] }
      entry_date = entry.date.to_date
      tags.filter_map do |tag|
        date = dates[tag.downcase]
        next unless date

        { tag: tag, date: date.iso8601, age: ApplicationController.helpers.tag_relative_date(date, entry_date) }
      end
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
