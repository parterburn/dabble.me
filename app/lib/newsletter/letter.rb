# frozen_string_literal: true

class Newsletter
  # One letter: a Markdown file that opens with its subject and preview text
  # between `---` lines, followed by the body. {{name}} placeholders are filled
  # in per person.
  class Letter
    PLACEHOLDER = /\{\{\s*(\w+)\s*\}\}/
    FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n/m

    Rendered = Struct.new(:subject, :preview, :markdown, :html, :text, keyword_init: true)

    def initialize(path)
      raise Newsletter::Error, "No letter at #{path}" unless path.file?

      source = path.read
      match = source.match(FRONT_MATTER)
      raise Newsletter::Error, "#{path}: start the letter with --- subject and preview ---" unless match

      header = YAML.safe_load(match[1]) || {}
      @path = path
      @subject = header["subject"].to_s
      @preview = header["preview"].to_s
      @body = match.post_match.strip
      raise Newsletter::Error, "#{path}: subject is missing" if @subject.blank?
    end

    def render(values)
      markdown = fill(@body, values)
      Rendered.new(
        subject: fill(@subject, values),
        preview: fill(@preview, values),
        markdown: markdown,
        html: self.class.markdown_to_html(markdown),
        text: self.class.markdown_to_text(markdown)
      )
    end

    # Anything still to be filled in by hand before this can go out.
    def unfinished?
      [@subject, @preview, @body].any? { |part| part.include?("TODO") }
    end

    def self.markdown_to_html(markdown)
      renderer = Redcarpet::Render::HTML.new(filter_html: true, safe_links_only: true)
      Redcarpet::Markdown.new(renderer, autolink: true, no_intra_emphasis: true).render(markdown)
    end

    # The plain-text part: the Markdown with links written out and emphasis
    # marks removed.
    def self.markdown_to_text(markdown)
      markdown
        .gsub(/\[([^\]]+)\]\(([^)]+)\)/) { Regexp.last_match(1) == Regexp.last_match(2) ? Regexp.last_match(2) : "#{Regexp.last_match(1)} (#{Regexp.last_match(2)})" }
        .gsub(/\*\*([^*]+)\*\*/, '\1')
        .gsub(/^\#{1,6}\s+/, "")
    end

    private

    # A placeholder nothing fills is a typo; fail rather than send it.
    def fill(text, values)
      text.gsub(PLACEHOLDER) do
        name = Regexp.last_match(1)
        values.fetch(name) { raise Newsletter::Error, "#{@path}: nothing fills {{#{name}}}" }
      end
    end
  end
end
