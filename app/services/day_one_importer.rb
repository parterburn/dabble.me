# frozen_string_literal: true

require "zip"

# Imports a Day One JSON ZIP export into Dabble Me entries.
#
# Expected ZIP layout (Day One 2.x+):
#   Journal.json          # or any *.json with an "entries" array
#   photos/<md5>.jpeg     # optional media
#   photos/<md5>.png
#
# Multiple Day One entries on the same calendar day are merged into one Dabble
# entry (Dabble Me is one-entry-per-day). Existing Dabble entries for a date
# are skipped. At most one image is attached per day (single photo, or a
# collage of up to CollageGenerator::MAX_IMAGES photos).
class DayOneImporter
  MOMENT_EMBED = /!\[.*?\]\(dayone-moment:\/\/[^)]+\)/i
  PHOTO_TYPES = {
    "jpeg" => %w[.jpeg .jpg],
    "jpg" => %w[.jpg .jpeg],
    "png" => %w[.png],
    "gif" => %w[.gif],
    "heic" => %w[.heic .heif],
    "heif" => %w[.heif .heic],
    "webp" => %w[.webp]
  }.freeze

  Result = Struct.new(:imported, :skipped, :errors, keyword_init: true)

  def initialize(user:, zip_path:)
    @user = user
    @zip_path = zip_path
    @imported = 0
    @skipped = []
    @errors = []
  end

  def import!
    Dir.mktmpdir("day_one_import") do |tmpdir|
      extract_zip!(tmpdir)
      json_paths = Dir.glob(File.join(tmpdir, "**", "*.json")).reject { |p| p.include?("/__MACOSX/") }
      raise ArgumentError, "No JSON journal file found in the ZIP" if json_paths.empty?

      json_paths.each { |path| import_json_file(path, tmpdir) }
    end

    Result.new(imported: @imported, skipped: @skipped, errors: @errors)
  end

  private

  def extract_zip!(tmpdir)
    Zip::File.open(@zip_path) do |zipfile|
      zipfile.each do |entry|
        next if entry.directory?
        next if entry.name.include?("..")
        next if entry.name.include?("__MACOSX/")

        dest = File.expand_path(File.join(tmpdir, entry.name))
        next unless dest.start_with?(File.expand_path(tmpdir) + File::SEPARATOR) || dest == File.expand_path(tmpdir)

        FileUtils.mkdir_p(File.dirname(dest))
        File.open(dest, "wb") do |f|
          f.write(entry.get_input_stream.read)
        end
      end
    end
  end

  def import_json_file(path, tmpdir)
    data = JSON.parse(File.read(path))
    entries = data["entries"]
    unless entries.is_a?(Array)
      @errors << "#{File.basename(path)}: missing entries array"
      return
    end

    grouped = entries.group_by { |raw| entry_date(raw) }
    grouped.each do |date, day_entries|
      import_day(date, day_entries, tmpdir)
    end
  rescue JSON::ParserError => e
    @errors << "#{File.basename(path)}: invalid JSON (#{e.message})"
  end

  def import_day(date, day_entries, tmpdir)
    if date.blank?
      @errors << "Entry missing creationDate"
      return
    end

    if @user.existing_entry(date).present?
      @skipped << "Entry already exists for #{date}"
      return
    end

    bodies = day_entries.sort_by { |e| e["creationDate"].to_s }.filter_map { |e| format_body(e["text"]) }
    body = bodies.join("<hr>")
    if body.blank? && day_entries.none? { |e| Array(e["photos"]).any? }
      @skipped << "Empty entry for #{date}"
      return
    end

    entry = @user.entries.new(
      date: date,
      body: body.presence || "<p></p>",
      inspiration: day_one_inspiration
    )

    photo_paths = collect_photo_paths(day_entries, tmpdir)
    attach_photos!(entry, photo_paths)

    if entry.save
      @imported += 1
    else
      @errors << "#{date}: #{entry.errors.full_messages.to_sentence}"
    end
  rescue StandardError => e
    @errors << "#{date}: #{e.message}"
    Sentry.capture_exception(e, extra: { date: date, user_id: @user.id })
  end

  def entry_date(raw)
    created = raw["creationDate"].presence
    return nil if created.blank?

    zone = Time.find_zone(raw["timeZone"].presence) || ActiveSupport::TimeZone["UTC"]
    zone.parse(created).to_date
  rescue ArgumentError, TypeError
    Time.zone.parse(created).to_date
  rescue StandardError
    nil
  end

  def format_body(text)
    cleaned = text.to_s.gsub(MOMENT_EMBED, "").strip
    return nil if cleaned.blank?

    html = markdown.render(cleaned)
    html.gsub!(/\A(\s*<p>\s*<\/p>\s*)/, "")
    html.gsub!(/(\s*<p>\s*<\/p>\s*)\z/, "")
    html.presence
  end

  def markdown
    @markdown ||= Redcarpet::Markdown.new(
      Redcarpet::Render::HTML.new(hard_wrap: true, filter_html: true, escape_html: true),
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      no_intra_emphasis: true
    )
  end

  def day_one_inspiration
    @day_one_inspiration ||= Inspiration.find_or_create_by!(category: "Day One") do |inspiration|
      inspiration.body = "Imported from Day One"
    end
  end

  def collect_photo_paths(day_entries, tmpdir)
    paths = []
    day_entries.sort_by { |e| e["creationDate"].to_s }.each do |raw|
      Array(raw["photos"]).sort_by { |p| p["orderInEntry"].to_i }.each do |photo|
        path = resolve_photo_path(photo, tmpdir)
        paths << path if path
        break if paths.size >= CollageGenerator::MAX_IMAGES
      end
      break if paths.size >= CollageGenerator::MAX_IMAGES
    end
    paths
  end

  def resolve_photo_path(photo, tmpdir)
    md5 = photo["md5"].to_s
    return nil if md5.blank? || md5.include?("..") || md5.include?("/")

    type = photo["type"].to_s.downcase.presence || "jpeg"
    extensions = PHOTO_TYPES[type] || [".#{type}", ".jpeg", ".jpg", ".png"]

    extensions.each do |ext|
      candidate = File.join(tmpdir, "photos", "#{md5}#{ext}")
      return candidate if File.file?(candidate)
    end

    # Some exports nest media under a journal folder or use unexpected extensions.
    Dir.glob(File.join(tmpdir, "**", "#{md5}.*")).find do |path|
      next if path.include?("__MACOSX/")
      next if path.include?("..")

      File.file?(path)
    end
  end

  def attach_photos!(entry, photo_paths)
    return if photo_paths.blank?

    if photo_paths.one?
      File.open(photo_paths.first, "rb") { |f| entry.image = f }
      return
    end

    collage = CollageGenerator.new(urls: photo_paths, user: @user).tempfile
    if collage
      entry.image = collage
    else
      File.open(photo_paths.first, "rb") { |f| entry.image = f }
    end
  ensure
    if defined?(collage) && collage
      collage.close
      collage.unlink
    end
  end
end
