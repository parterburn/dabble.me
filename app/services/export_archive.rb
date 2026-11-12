# frozen_string_literal: true

# Writes a ZIP of entries to a file: an images/ folder holding each entry's
# photo, journal.md (ExportMarkdown) and journal.html (ExportHtml), which show
# those photos. Entries are read in batches and photos one at a time, so a
# large journal never has to fit in memory.
class ExportArchive
  BATCH_SIZE = 200

  Result = Struct.new(:entry_count, :image_count, :skipped_image_count, keyword_init: true)

  def initialize(entries)
    @entries = entries.unscope(:order)
  end

  def write_to(path)
    result = Result.new(entry_count: ids.size, image_count: 0, skipped_image_count: 0)

    Zip::OutputStream.open(path) do |zip|
      # Photos first, so the documents only point to ones that made it in.
      written = {}
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
        written[entry.id] = name
        result.image_count += 1
      end

      zip.put_next_entry("journal.md")
      zip.write(ExportMarkdown.header)
      each_entry { |entry| zip.write(ExportMarkdown.entry(entry, image: written[entry.id])) }

      zip.put_next_entry("journal.html")
      zip.write(ExportHtml.header(result.entry_count))
      each_entry { |entry| zip.write(ExportHtml.entry(entry, image: written[entry.id])) }
      zip.write(ExportHtml.footer)
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

  # { entry id => "images/2026-01-02.jpg" }, worked out up front so two
  # photos from one day get different names.
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

  # The photo's bytes, or nil when it can't be read (a file missing from
  # storage should cost one photo, not the whole export).
  def image_data(entry)
    entry.image.read
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { entry_id: entry.id, reason: "Export could not read an image" })
    nil
  end
end
