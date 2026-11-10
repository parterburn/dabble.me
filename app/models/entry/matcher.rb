class Entry
  # Matches entry bodies against a search term in Ruby, so no query has to read
  # entry text in SQL. Shared by the search page, exports, the API, MCP tools,
  # the reminder-email word filter and AI reflection context.
  #
  # Query styles (see .parse):
  #   foo OR bar   -> body contains any term (case-insensitive)
  #   "exact word" -> whole-word phrase match (case-insensitive)
  #   anything     -> body contains the substring (case-insensitive)
  class Matcher
    BATCH_SIZE = 1000
    WORD_CHAR = "[[:alnum:]_]".freeze

    # Returns nil when the term has nothing to search for.
    def self.parse(term)
      term = term.to_s
      return nil if term.blank?

      if term.include?(" OR ")
        any(term.split(" OR "))
      elsif term.include?('"')
        phrase(term.delete('"'))
      else
        any([term])
      end
    end

    # Body contains any of the given substrings.
    def self.any(terms)
      terms = terms.map { |t| t.to_s.strip.downcase }.reject(&:blank?)
      new(substrings: terms) if terms.any?
    end

    # Body contains the phrase starting and ending on word boundaries.
    def self.phrase(phrase)
      phrase = phrase.to_s.strip
      return nil if phrase.blank?

      # Same rule Postgres applied with \m...\M: the phrase must begin at the
      # start of a word and stop at the end of one.
      new(pattern: /(?<!#{WORD_CHAR})(?=#{WORD_CHAR})#{Regexp.escape(phrase)}(?<=#{WORD_CHAR})(?!#{WORD_CHAR})/i)
    end

    def initialize(substrings: [], pattern: nil)
      @substrings = substrings
      @pattern = pattern
    end

    def match?(body)
      return false if body.blank?
      return @pattern.match?(body) if @pattern

      lowered = body.downcase
      @substrings.any? { |term| lowered.include?(term) }
    end

    # Ids of every entry in the relation whose body matches.
    def ids(relation)
      matched = []
      relation.unscope(:order).in_batches(of: BATCH_SIZE) do |batch|
        batch.pluck(:id, :body).each { |id, body| matched << id if match?(body) }
      end
      matched
    end

    # The relation narrowed to matching entries; still a relation, so callers
    # can order, count and paginate it.
    def filter(relation)
      relation.where(id: ids(relation))
    end

    # The first `count` matching entries in the relation's own order, without
    # reading further than needed.
    def first(relation, count)
      found = []
      offset = 0
      loop do
        page = relation.offset(offset).limit(BATCH_SIZE).to_a
        page.each do |entry|
          found << entry if match?(entry.body)
          return found if found.size >= count
        end
        return found if page.size < BATCH_SIZE

        offset += BATCH_SIZE
      end
    end
  end
end
