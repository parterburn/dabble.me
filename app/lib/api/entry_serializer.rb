# frozen_string_literal: true

module Api
  # JSON shape for /api/v1 entries (iOS app). Bodies are sent as text (light Markdown
  # from Entry#text_body) so the client never has to render stored HTML.
  class EntrySerializer
    EXCERPT_LENGTH = 280
    EDITABLE_TAGS = %w[p br].freeze

    def self.summary(entry)
      new(entry).summary
    end

    def self.full(entry)
      new(entry).full
    end

    def self.editable_text(entry)
      new(entry).editable_text
    end

    # Plain text -> the same HTML the web compose / MCP create paths store.
    def self.html_from_plain(plain)
      ActionController::Base.helpers.simple_format(ERB::Util.html_escape(plain.to_s.strip), {}, sanitize: false)
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
        body_text: entry.text_body.to_s.strip,
        editable_text: editable_text,
        songs: songs,
        web_url: Mcp::Tools::Helpers.entry_public_url(entry)
      )
    end

    # Plain text the app may edit and send back, or nil when the stored HTML has
    # anything beyond <p>/<br> (links, formatting, merged <hr> sections, AI replies,
    # email markup). Those stay web-only so an in-app edit can never drop formatting.
    def editable_text
      return nil if entry.body.blank?

      fragment = Nokogiri::HTML5.fragment(entry.body)
      nodes = []
      fragment.traverse { |node| nodes << node unless node.equal?(fragment) }
      simple = nodes.all? do |node|
        node.text? || (node.element? && EDITABLE_TAGS.include?(node.name) && node.attributes.empty?)
      end
      return nil unless simple

      blocks = []
      loose = +''
      fragment.children.each do |node|
        if node.element? && node.name == 'p'
          blocks << loose.strip if loose.strip.present?
          loose = +''
          blocks << paragraph_text(node)
        elsif node.element? # top-level <br>
          loose << "\n"
        else
          loose << node.text
        end
      end
      blocks << loose.strip if loose.strip.present?
      blocks.reject(&:blank?).join("\n\n").presence
    end

    private

    attr_reader :entry

    def paragraph_text(paragraph)
      text = paragraph.children.map { |child| child.element? ? "\n" : child.text.gsub(/\s+/, ' ') }.join
      text.split("\n", -1).map(&:strip).join("\n").strip
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
