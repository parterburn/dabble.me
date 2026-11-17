# frozen_string_literal: true

module Api
  # Converts entry HTML to and from the structured document the iOS editor works with:
  #
  #   [{ "type" => "paragraph", "runs" => [{ "text" => "Hi ", }, { "text" => "there", "bold" => true }] },
  #    { "type" => "bullet", "runs" => [...] }, { "type" => "number", "runs" => [...] }, { "type" => "rule" }]
  #
  # Runs may set bold / italic / underline / link; "\n" inside a run is a line break.
  # A list item inside another's list has a "level" (1 for the first list in, up to
  # MAX_LIST_LEVEL); top-level items have none.
  #
  # Only the formatting the web editor (Summernote) and email ingestion produce is
  # editable: p, div, span, br, b/strong, i/em, u, a, ul/ol/li and hr (merged replies).
  # Anything else — inline styles, blockquotes, images, unknown attributes, text after a
  # list inside a list item, a list under an item with no text — makes from_html return nil.
  # Such an entry is still editable in the app, from simplified_from_html: the same document
  # with what it can't hold left out or flattened. The app says so before saving, since saving
  # rewrites the entry without that formatting.
  module EntryDocument
    class NotEditable < StandardError; end
    class InvalidDocument < StandardError; end

    BLOCK_TYPES = %w[paragraph bullet number rule].freeze
    LIST_TAGS = { 'bullet' => 'ul', 'number' => 'ol' }.freeze
    MAX_LIST_LEVEL = 5
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

    # A document for HTML from_html won't take, by simplifying it first: attributes and styles
    # go, as do images and other embedded things; headings become bold paragraphs; quotes,
    # tables and anything else unknown keep their text; a list the document can't nest is
    # flattened. Always a document when there's any text at all (plain paragraphs at worst).
    # @return [Array<Hash>, nil] nil only when there's nothing to show.
    def simplified_from_html(html)
      return nil if html.blank?

      fragment = Nokogiri::HTML5.fragment(html)
      simplify!(fragment)
      parse_blocks(fragment.children).presence || text_paragraphs(fragment)
    rescue NotEditable
      text_paragraphs(Nokogiri::HTML5.fragment(html))
    end

    # Builds stored HTML from a client document. Raises InvalidDocument on bad input.
    # `links: false` keeps a link's text but drops the link (hyperlinks are PRO).
    def to_html(document, links: true)
      blocks = validate!(document)
      blocks.each { |block| Array(block['runs']).each { |run| run.delete('link') } } unless links
      html = []
      lists = [] # the open lists' tags, outermost first; each has an item open
      # An item with nothing nested closes on its own line ("<li>x</li>").
      close_item = lambda do
        html.last.start_with?('<li>') && !html.last.end_with?('</li>') ? html[-1] += '</li>' : html << '</li>'
      end
      close_list = lambda do
        close_item.call
        html << "</#{lists.pop}>"
      end

      blocks.each do |block|
        tag = LIST_TAGS[block['type']]
        # A list goes at most one level deeper than the item before it.
        level = tag ? [block['level'].to_i, lists.size].min : -1
        close_list.call while lists.size > level + 1
        close_list.call if tag && lists.size == level + 1 && lists.last != tag

        case block['type']
        when 'paragraph' then html << "<p>#{runs_html(block['runs'])}</p>" if runs_text(block['runs']).strip.present?
        when 'bullet', 'number'
          if lists.size == level + 1
            close_item.call
          else
            html << "<#{tag}>"
            lists << tag
          end
          html << "<li>#{runs_html(block['runs'])}"
        when 'rule' then html << '<hr>'
        end
      end
      close_list.call while lists.any?
      html.join("\n")
    end

    def plain_text(document)
      validate!(document).filter_map { |block| runs_text(block['runs']).strip.presence }.join("\n\n")
    end

    # -- simplifying HTML the document can't hold -----------------------------------

    DROPPED_TAGS = %w[img picture video audio iframe object embed svg canvas script style head meta link title
                      input button select textarea form map area source track noscript template].freeze
    LINE_TAGS = %w[blockquote pre table thead tbody tfoot tr section article header footer aside main nav
                   figure figcaption address details summary dl dt dd center fieldset caption].freeze
    HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].freeze
    KEPT_TAGS = (%w[p div span br a ul ol li hr] + INLINE_FORMATS.keys).freeze

    def simplify!(fragment)
      fragment.xpath('.//comment()').each(&:remove)
      fragment.css(DROPPED_TAGS.join(',')).each(&:remove)
      # Deepest first, so replacing an element never loses one still to be visited.
      fragment.xpath('.//*').reverse_each do |node|
        if node.name == 'a'
          href = node['href'].to_s.strip
          next node.replace(node.children) unless safe_link?(href)

          node.attributes.each_key { |name| node.remove_attribute(name) unless name == 'href' }
          node['href'] = href
          next
        end
        node.attributes.each_key { |name| node.remove_attribute(name) }
        if HEADING_TAGS.include?(node.name)
          node.inner_html = "<strong>#{node.inner_html}</strong>"
          node.name = 'p'
        elsif LINE_TAGS.include?(node.name)
          node.name = 'div'
        elsif %w[td th].include?(node.name)
          node.add_next_sibling(' ')
          node.replace(node.children)
        elsif !KEPT_TAGS.include?(node.name)
          node.replace(node.children) # its text stays; what it meant doesn't
        end
      end
      simplify_lists!(fragment)
    end

    # Lists as the document can hold them: every list under an item with text, nothing after a
    # list inside an item, and no deeper than MAX_LIST_LEVEL.
    def simplify_lists!(fragment)
      fragment.css('ul, ol').each do |list|
        next unless list.parent # already folded into another

        # Anything loose in a list (text, a paragraph) becomes an item.
        list.children.each do |child|
          next if blank_node?(child) || (child.element? && (child.name == 'li' || list?(child)))

          item = Nokogiri::XML::Node.new('li', list.document)
          child.replace(item)
          item.add_child(child)
        end
        too_deep = list.ancestors.count { |ancestor| list?(ancestor) } > MAX_LIST_LEVEL
        owner = list.parent
        if owner.name == 'li'
          before = owner.children.take_while { |child| child != list }
          orphan = before.all? { |child| blank_node?(child) || child.text.strip.empty? }
          after = owner.children.drop_while { |child| child != list }.drop(1).reject { |child| blank_node?(child) || list?(child) }
          # What follows the list in its item goes on as an item of its own.
          if after.any?
            item = Nokogiri::XML::Node.new('li', list.document)
            after.each { |child| item.add_child(child) }
            owner.add_next_sibling(item)
          end
          # No text to sit under, or too deep: its items join the list around it.
          if orphan || too_deep
            list.children.reverse_each { |child| owner.add_next_sibling(child) }
            list.remove
            owner.remove if orphan && owner.text.strip.empty?
          end
        elsif list?(owner)
          previous = list.previous_element
          if previous.nil? || previous.name != 'li' || too_deep
            list.replace(list.children)
          end
        end
      end
    end

    # The last resort: the text alone, a paragraph for each block of it.
    def text_paragraphs(fragment)
      fragment.css('br').each { |br| br.replace("\n") }
      fragment.css('p, div, li, tr, h1, h2, h3, h4, h5, h6, blockquote').each { |node| node.add_next_sibling("\n\n") }
      fragment.text.split(/\n{2,}/).filter_map do |text|
        text = text.gsub(/[ \t]+/, ' ').gsub(/ *\n */, "\n").strip
        { 'type' => 'paragraph', 'runs' => [{ 'text' => text }] } if text.present?
      end.presence
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

    # A list's items in order, each followed by the items of any list inside it (a level deeper).
    def list_items(list, level = 0)
      raise NotEditable if level > MAX_LIST_LEVEL

      type = list.name == 'ol' ? 'number' : 'bullet'
      blocks = []
      list.children.each do |item|
        next if blank_node?(item)
        raise NotEditable unless item.element?

        check_attributes!(item)
        if list?(item) # a list straight inside a list, as browsers' indent command leaves it
          # With no item before it there's nothing for it to sit under.
          raise NotEditable if blocks.empty?

          blocks.concat(list_items(item, level + 1))
          next
        end
        raise NotEditable unless item.name == 'li'

        children = item.children.to_a
        text_count = children.index { |child| list?(child) } || children.size
        block = { 'type' => type, 'runs' => clean_runs(children.first(text_count).flat_map { |child| inline_runs(child, {}) }) }
        block['level'] = level if level.positive?
        # An item with no text of its own that holds a list: the app drops empty items, which
        # would leave that list without the item it's under, so the entry stays web-only.
        raise NotEditable if block['runs'].empty? && text_count < children.size && children.drop(text_count).any? { |child| list?(child) }

        blocks << block
        # Only lists may follow: text after a nested list has nowhere to go in the document.
        children.drop(text_count).each do |child|
          next if blank_node?(child)
          raise NotEditable unless list?(child)

          check_attributes!(child)
          blocks.concat(list_items(child, level + 1))
        end
      end
      blocks
    end

    def list?(node)
      node.element? && LIST_TAGS.value?(node.name)
    end

    def blank_node?(node)
      node.comment? || (node.text? && node.text.strip.empty?)
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
        clean = { 'type' => type, 'runs' => runs }
        level = block['level'].to_i.clamp(0, MAX_LIST_LEVEL)
        clean['level'] = level if level.positive? && LIST_TAGS.key?(type)
        clean
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
