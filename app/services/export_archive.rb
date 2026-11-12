# frozen_string_literal: true

# Writes a ZIP of entries to a file: entries.txt, entries.json and an images/
# folder holding each entry's photo. Entries are read in batches and photos
# one at a time, so a large journal never has to fit in memory.
class ExportArchive
  BATCH_SIZE = 200

  Result = Struct.new(:entry_count, :image_count, :skipped_image_count, keyword_init: true)

  def initialize(entries)
    @entries = entries.unscope(:order)
  end

  def write_to(path)
    result = Result.new(entry_count: ids.size, image_count: 0, skipped_image_count: 0)

    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry("entries.txt")
      each_entry { |entry| zip.write(text_for(entry)) }

      zip.put_next_entry("entries.json")
      zip.write("[\n")
      each_entry.with_index do |entry, index|
        zip.write(",\n") unless index.zero?
        zip.write(JSON.pretty_generate(json_for(entry)))
      end
      zip.write("\n]\n")

      each_entry do |entry|
        name = image_names[entry.id]
        next unless name

        data = image_data(entry)
        if data.nil?
          result.skipped_image_count += 1
          next
        end

        # Photos are already compressed; storing them as they are is faster.
        zip.put_next_entry(name, nil, nil, Zip::Entry::STORED)
        zip.write(data)
        result.image_count += 1
      end
    end

    result
  end

  private

  # In date order, oldest first.
  def ids
    @ids ||= @entries.order(:date, :id).pluck(:id)
  end

  def each_entry
    return enum_for(:each_entry) unless block_given?

    ids.each_slice(BATCH_SIZE) do |slice|
      by_id = Entry.unscoped.where(id: slice).index_by(&:id)
      slice.each { |id| yield by_id[id] if by_id[id] }
    end
  end

  # { entry id => "images/2026-01-02.jpg" }, worked out up front so the text
  # and JSON files can name each photo before it is written.
  def image_names
    @image_names ||= begin
      taken = Set.new
      rows = @entries.where.not(image: [nil, ""]).order(:date, :id).pluck(:id, :date, :image)
      rows.to_h do |id, date, filename|
        extension = File.extname(filename.to_s).downcase.presence || ".jpg"
        name = "images/#{date.strftime('%Y-%m-%d')}#{extension}"
        name = "images/#{date.strftime('%Y-%m-%d')}-#{id}#{extension}" if taken.include?(name)
        taken << name
        [id, name]
      end
    end
  end

  def text_for(entry)
    text = +"## #{entry.date.strftime('%Y-%m-%d')}\n"
    body = entry.body.present? ? entry.text_body.to_s.strip : ""
    text << "#{body}\n" if body.present?
    text << "Photo: #{image_names[entry.id]}\n" if image_names[entry.id]
    text << "\n"
  end

  def json_for(entry)
    json = { date: entry.date.strftime("%Y-%m-%d"), body: entry.body.to_s.strip }
    json[:image] = image_names[entry.id] if image_names[entry.id]
    json
  end

  # The photo's bytes, or nil when it can't be read (a file missing from
  # storage should cost one photo, not the whole export).
  def image_data(entry)
    entry.image.read
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { entry_id: entry.id, reason: "Export could not read an image" })
    nil
  end
end
