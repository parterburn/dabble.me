# frozen_string_literal: true

module Api
  # Converts entry HTML to and from the structured document the iOS editor works with:
  #
  #   [{ "type" => "paragraph", "runs" => [{ "text" => "Hi ", }, { "text" => "there", "bold" => true }] },
  #    { "type" => "bullet", "runs" => [...] }, { "type" => "number", "runs" => [...] }, { "type" => "rule" }]
  #
  # Runs may set bold / italic / underline / link; "\n" inside a run is a line break.
  #
  # Only the formatting the web editor (Summernote) and email ingestion produce is
  # editable: p, div, span, br, b/strong, i/em, u, a, ul/ol/li and hr (merged replies).
  # Anything else — inline styles, blockquotes, images, AI replies (data-content),
  # nested lists — makes from_html return nil and the entry stays web-only, so an app
  # edit can never silently drop formatting.
  module EntryDocument
    class NotEditable < StandardError; end
    class InvalidDocument < StandardError; end

    BLOCK_TYPES = %w[paragraph bullet number rule].freeze
    INLINE_FORMATS = { 'b' => :bold, 'strong' => :bold, 'i' => :italic, 'em' => :italic, 'u' => :underline }.freeze
    ALLOWED_ATTRIBUTES = { 'a' => %w[href target rel] }.freeze
    LINK_SCHEMES = %w[http https mailto].freeze
    MAX_BLOCKS = 2_000
    MAX_TEXT_BYTES = 200_000

    module_function

    # @return [Array<Hash>, nil] nil when the HTML has anything the app can't edit faithfully.
    def from_html(html)
      return nil if html.blank?

      fragment = Nokogiri::HTML5.fragment(html)
      blocks = parse_blocks(fragment.children)
      blocks.presence
    rescue NotEditable
      nil
    end

    # Builds stored HTML from a client document. Raises InvalidDocument on bad input.
    def to_html(document)
      blocks = validate!(document)
      html = []
      open_list = nil

      blocks.each do |block|
        list_tag = { 'bullet' => 'ul', 'number' => 'ol' }[block['type']]
        if list_tag != open_list
          html << "</#{open_list}>" if open_list
          html << "<#{list_tag}>" if list_tag
          open_list = list_tag
        end

        case block['type']
        when 'paragraph' then html << "<p>#{runs_html(block['runs'])}</p>" if runs_text(block['runs']).strip.present?
        when 'bullet', 'number' then html << "<li>#{runs_html(block['runs'])}</li>"
        when 'rule' then html << '<hr>'
        end
      end
      html << "</#{open_list}>" if open_list
      html.join("\n")
    end

    def plain_text(document)
      validate!(document).filter_map { |block| runs_text(block['runs']).strip.presence }.join("\n\n")
    end

    # -- HTML -> document ---------------------------------------------------------

    def parse_blocks(nodes)
      blocks = []
      lines = nil # runs of the paragraph being built from loose inline content / div lines
      after_div_line = false

      flush = lambda do
        runs = clean_runs(lines || [])
        blocks << { 'type' => 'paragraph', 'runs' => runs } if runs.any?
        lines = nil
        after_div_line = false
      end
      # Each <div> is its own line; loose inline content continues the current line.
      append = lambda do |runs, new_line:|
        lines ||= []
        lines << { 'text' => "\n" } if lines.any? && (new_line || after_div_line)
        lines.concat(runs)
        after_div_line = new_line
      end

      nodes.each do |node|
        if node.text?
          next if node.text.strip.empty? && (lines.nil? || after_div_line)

          append.call(inline_runs(node, {}), new_line: false)
        elsif node.comment?
          next
        elsif !node.element?
          raise NotEditable
        else
          check_attributes!(node)
          case node.name
          when 'p'
            flush.call
            runs = clean_runs(inline_children(node, {}))
            blocks << { 'type' => 'paragraph', 'runs' => runs } if runs.any?
          when 'div'
            if node.element_children.any? { |child| %w[p div ul ol hr].include?(child.name) }
              flush.call
              blocks.concat(parse_blocks(node.children))
            else
              # inline_children raises NotEditable for anything unsupported (e.g. an <img>
              # in an otherwise empty div), so check it before treating the div as blank.
              runs = inline_children(node, {})
              if runs.all? { |run| run['text'].strip.empty? }
                flush.call # <div><br></div> is the blank line between paragraphs in email HTML
              else
                append.call(runs, new_line: true)
              end
            end
          when 'ul', 'ol'
            flush.call
            blocks.concat(list_items(node))
          when 'hr'
            flush.call
            blocks << { 'type' => 'rule' }
          when 'br'
            append.call([{ 'text' => "\n" }], new_line: false)
          else
            append.call(inline_runs(node, {}), new_line: false)
          end
        end
      end
      flush.call
      blocks
    end

    def list_items(list)
      type = list.name == 'ol' ? 'number' : 'bullet'
      list.children.filter_map do |item|
        next if item.text? && item.text.strip.empty?
        raise NotEditable unless item.element? && item.name == 'li'

        check_attributes!(item)
        { 'type' => type, 'runs' => clean_runs(inline_children(item, {})) }
      end
    end

    def inline_children(node, format)
      node.children.flat_map { |child| inline_runs(child, format) }
    end

    def inline_runs(node, format)
      return [] if node.comment?
      return [format.merge('text' => node.text.gsub(/[ \t\r\n]+/, ' '))] if node.text?
      raise NotEditable unless node.element?

      check_attributes!(node)
      case node.name
      when 'br' then [format.merge('text' => "\n")]
      when 'span' then inline_children(node, format)
      when 'a'
        href = node['href'].to_s.strip
        raise NotEditable unless safe_link?(href)

        inline_children(node, format.merge('link' => href))
      when *INLINE_FORMATS.keys
        inline_children(node, format.merge(INLINE_FORMATS[node.name].to_s => true))
      when 'p', 'div'
        # Summernote sometimes wraps list item text in <p>; treat as a line.
        inline_children(node, format) + [format.merge('text' => "\n")]
      else
        raise NotEditable
      end
    end

    def check_attributes!(node)
      allowed = ALLOWED_ATTRIBUTES.fetch(node.name, [])
      raise NotEditable unless node.attributes.keys.all? { |name| allowed.include?(name) }
    end

    # Collapses HTML whitespace the way a browser renders it and merges identical runs.
    def clean_runs(runs)
      merged = []
      runs.each do |run|
        text = run['text'].gsub(/ *\n */, "\n")
        next if text.empty?

        previous = merged.last
        if previous
          # No leading spaces at the start of a line or after a space; no trailing spaces before a break.
          text = text.sub(/\A +/, '') if previous['text'].end_with?("\n", ' ')
          previous['text'] = previous['text'].sub(/ +\z/, '') if text.start_with?("\n")
        end
        next if text.empty?

        if previous && previous.except('text') == run.except('text')
          previous['text'] += text
        else
          merged << run.merge('text' => text)
        end
      end

      if merged.any?
        merged.first['text'] = merged.first['text'].sub(/\A\s+/, '')
        merged.last['text'] = merged.last['text'].sub(/\s+\z/, '')
      end
      merged.reject { |run| run['text'].empty? }
    end

    def safe_link?(href)
      uri = URI.parse(href)
      LINK_SCHEMES.include?(uri.scheme.to_s.downcase) && (uri.scheme.downcase == 'mailto' || uri.host.present?)
    rescue URI::InvalidURIError
      false
    end

    # -- document -> HTML ---------------------------------------------------------

    def validate!(document)
      blocks = document.respond_to?(:to_unsafe_h) ? document.to_unsafe_h : document
      blocks = blocks.map { |block| block.respond_to?(:to_unsafe_h) ? block.to_unsafe_h : block } if blocks.is_a?(Array)
      raise InvalidDocument, 'document must be a list of blocks' unless blocks.is_a?(Array) && blocks.size <= MAX_BLOCKS

      total = 0
      blocks.map do |block|
        raise InvalidDocument, 'each block must be an object' unless block.is_a?(Hash)

        type = block['type'].to_s
        raise InvalidDocument, "unknown block type #{type.inspect}" unless BLOCK_TYPES.include?(type)
        next { 'type' => 'rule' } if type == 'rule'

        runs = Array(block['runs']).map do |run|
          run = run.respond_to?(:to_unsafe_h) ? run.to_unsafe_h : run
          raise InvalidDocument, 'each run must be an object with text' unless run.is_a?(Hash) && run['text'].is_a?(String)

          total += run['text'].bytesize
          raise InvalidDocument, 'entry is too long' if total > MAX_TEXT_BYTES

          clean = { 'text' => run['text'] }
          %w[bold italic underline].each { |key| clean[key] = true if run[key] == true }
          link = run['link'].to_s.strip
          clean['link'] = link if link.present? && safe_link?(link)
          clean
        end
        { 'type' => type, 'runs' => runs }
      end
    end

    def runs_html(runs)
      runs.map do |run|
        html = ERB::Util.html_escape(run['text']).to_s.gsub(/\r\n?|\n/, '<br>')
        html = "<u>#{html}</u>" if run['underline']
        html = "<em>#{html}</em>" if run['italic']
        html = "<strong>#{html}</strong>" if run['bold']
        html = %(<a href="#{ERB::Util.html_escape(run['link'])}" target="_blank">#{html}</a>) if run['link']
        html
      end.join
    end

    def runs_text(runs)
      Array(runs).sum('') { |run| run['text'].to_s }
    end
  end
end
