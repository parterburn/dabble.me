module Mcp
  class EntrySearch
    MAX_LIMIT = 50

    def initialize(user:)
      @user = user
    end

    def search(query:, limit: 10, since: nil, until_date: nil, has_images: nil)
      relation = filtered_entries(since: since, until_date: until_date, has_images: has_images)
      relation = apply_query(relation, query)

      entries = relation.limit(normalized_limit(limit))

      {
        total_matches: relation.count,
        entries: entries.map { |entry| serialize_entry(entry) }
      }
    end

    def list(limit: 10, since: nil, until_date: nil, has_images: nil)
      relation = filtered_entries(since: since, until_date: until_date, has_images: has_images)
      entries = relation.limit(normalized_limit(limit))

      {
        total_matches: relation.count,
        entries: entries.map { |entry| serialize_entry(entry) }
      }
    end

    def analyze(query: nil, since: nil, until_date: nil)
      relation = filtered_entries(since: since, until_date: until_date)
      relation = apply_query(relation, query)

      matching_entries = relation.limit(500)
      text_bodies = matching_entries.map(&:text_body).compact
      hashtags = matching_entries.flat_map { |entry| entry.hashtags || [] }
      dates = matching_entries.map { |entry| entry.date.to_date }

      {
        total_matches: relation.count,
        date_range: {
          since: since,
          until: until_date
        },
        entry_count_by_year: dates.group_by(&:year).transform_values(&:count).sort.to_h,
        most_used_hashtags: hashtags.group_by(&:downcase).transform_values(&:count).sort_by { |_, count| -count }.first(10).map do |tag, count|
          { tag: tag, count: count }
        end,
        average_entry_length_words: average_words(text_bodies),
        sample_highlights: matching_entries.first(5).map do |entry|
          {
            id: entry.id,
            date: entry.date.to_date.iso8601,
            excerpt: excerpt(entry.text_body)
          }
        end
      }
    end

    private

    attr_reader :user

    def filtered_entries(since:, until_date:, has_images: nil)
      relation = user.entries.reorder(date: :desc, created_at: :desc)
      relation = relation.where('date >= ?', parse_date!(since)) if since.present?
      relation = relation.where('date <= ?', parse_date!(until_date).end_of_day) if until_date.present?
      relation = relation.where.not(image: [nil, '']) if has_images == true
      relation = relation.where(image: [nil, '']) if has_images == false
      relation
    end

    def apply_query(relation, query)
      return relation if query.blank?

      # Same query styles as the search page, matched in Ruby (Entry::Matcher).
      matcher = Entry::Matcher.parse(query.to_s.strip)
      # Only quote marks: nothing to narrow by.
      return relation if matcher.nil? && query.to_s.include?('"')
      return relation.none if matcher.nil?

      matcher.filter(relation)
    end

    def normalized_limit(limit)
      numeric = case limit
                when Integer
                  limit
                when Numeric
                  limit.to_i
                when String
                  raise ArgumentError, 'limit must be an integer' unless limit.match?(/\A\d+\z/)

                  limit.to_i
                else
                  raise ArgumentError, 'limit must be an integer'
                end
      [[numeric, 1].max, MAX_LIMIT].min
    end

    def parse_date!(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      raise ArgumentError, "Invalid date #{value.inspect}. Use YYYY-MM-DD."
    end

    def serialize_entry(entry)
      {
        id: entry.id,
        date: entry.date.to_date.iso8601,
        text_body: entry.text_body.to_s,
        hashtags: entry.hashtags || [],
        has_image: entry.image_stored?,
        image_url: image_url(entry)
      }
    end

    # The photo's public S3 URL (the bucket is public-read). Built from the image column, so
    # it costs no S3 request, except one for a HEIC original, to find its JPEG copy.
    def image_url(entry)
      entry.image.url if entry.image_stored?
    end

    def average_words(text_bodies)
      return 0 if text_bodies.empty?

      total_words = text_bodies.sum { |body| body.split(/\s+/).reject(&:blank?).size }
      (total_words.to_f / text_bodies.size).round(1)
    end

    def excerpt(text)
      text.to_s.gsub(/\s+/, ' ').strip.truncate(500)
    end
  end
end
