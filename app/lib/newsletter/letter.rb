# frozen_string_literal: true

class Newsletter
  # A newsletter's letter: one Markdown file that opens with its subject and
  # preview text between `---` lines, followed by the body.
  #
  # Everyone gets the same letter apart from two things. The subject and
  # preview may be given per variant, and a block between {{#name}} and
  # {{/name}} lines is kept only for the variant called `name`
  # ({{#one,two}} for either of two). {{name}} placeholders are filled in
  # per person.
  class Letter
    PLACEHOLDER = /\{\{\s*(\w+)\s*\}\}/
    FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n/m
    BLOCK = /^\{\{#([\w,]+)\}\}[ \t]*\n(.*?)^\{\{\/\1\}\}[ \t]*\n?/m
    BLOCK_MARK = /\{\{[#\/][\w,]+\}\}/

    Rendered = Struct.new(:subject, :preview, :markdown, :html, :text, keyword_init: true)

    def initialize(path, variant_names)
      raise Newsletter::Error, "No letter at #{path}" unless path.file?

      source = path.read
      match = source.match(FRONT_MATTER)
      raise Newsletter::Error, "#{path}: start the letter with --- subject and preview ---" unless match

      header = YAML.safe_load(match[1]) || {}
      @path = path
      @variant_names = variant_names
      @subject = header["subject"]
      @preview = header["preview"]
      @body = match.post_match.strip
      check!
    end

    def render(values, variant:)
      markdown = fill(body_for(variant), values)
      Rendered.new(
        subject: fill(for_variant(@subject, variant), values),
        preview: fill(for_variant(@preview, variant), values),
        markdown: markdown,
        html: self.class.markdown_to_html(markdown),
        text: self.class.markdown_to_text(markdown)
      )
    end

    # Anything still to be filled in by hand before this can go out.
    def unfinished?
      [@subject, @preview, @body].any? { |part| part.to_s.include?("TODO") }
    end

    def self.markdown_to_html(markdown)
      # hard_wrap keeps the line breaks of a sign-off written on separate lines.
      renderer = Redcarpet::Render::HTML.new(filter_html: true, safe_links_only: true, hard_wrap: true)
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

    # Keeps the blocks for this variant, drops the others, and closes the gap
    # a dropped block leaves.
    def body_for(variant)
      @body.gsub(BLOCK) { Regexp.last_match(1).split(",").include?(variant) ? Regexp.last_match(2) : "" }.gsub(/\n{3,}/, "\n\n").strip
    end

    # A subject or preview is one line for everyone, or one per variant.
    def for_variant(value, variant)
      value.is_a?(Hash) ? value.fetch(variant).to_s : value.to_s
    end

    def check!
      @variant_names.each do |variant|
        raise Newsletter::Error, "#{@path}: subject is missing for #{variant}" if for_variant(@subject, variant).blank?

        for_variant(@preview, variant)
      end

      @body.scan(BLOCK).flat_map { |(names, _content)| names.split(",") }.each do |name|
        raise Newsletter::Error, "#{@path}: {{##{name}}} names no variant (#{@variant_names.join(', ')})" unless @variant_names.include?(name)
      end
      stray = @body.gsub(BLOCK, "")[BLOCK_MARK]
      raise Newsletter::Error, "#{@path}: #{stray} has no matching line; put block marks on lines of their own" if stray
    rescue KeyError => e
      raise Newsletter::Error, "#{@path}: subject and preview need a line for every variant (#{e.message})"
    end

    # A placeholder nothing fills is a typo; fail rather than send it.
    def fill(text, values)
      text.gsub(PLACEHOLDER) do
        name = Regexp.last_match(1)
        values.fetch(name) { raise Newsletter::Error, "#{@path}: nothing fills {{#{name}}}" }
      end
    end
  end
end
