class ExportEntriesJob < ActiveJob::Base
  queue_as :default

  def perform(user_id, format, options = {})
    user = User.find(user_id)
    options = options.with_indifferent_access
    only_images = options[:only_images]
    search_term = options[:search_term]
    year = options[:year]

    entries_scope = build_entries_scope(user, only_images, search_term, year)
    filename = build_filename(only_images, search_term, year, format)

    tempfile = Tempfile.new([filename.gsub(/\.\w+$/, ''), ".#{format}"])

    begin
      generate_export(tempfile, entries_scope, format, only_images)
      tempfile.rewind

      UserMailer.export_ready(user, tempfile, filename, format).deliver_now
    ensure
      tempfile.close
      tempfile.unlink
    end
  end

  private

  def build_entries_scope(user, only_images, search_term, year)
    if only_images
      user.entries.only_images.reorder(:date)
    elsif search_term.present?
      if search_term.include?(' OR ')
        filter_names = search_term.split(' OR ')
        sanitized_terms = filter_names.map { |term| ActiveRecord::Base.sanitize_sql_like(term.downcase) }
        base_scope = user.entries
        conditions = sanitized_terms.map { |term| base_scope.where("LOWER(entries.body) LIKE ?", "%#{term}%") }
        conditions.reduce(:or).reorder(:date)
      elsif search_term.include?('"')
        exact_phrase = search_term.delete('"')
        sanitized_phrase = Regexp.escape(exact_phrase)
        user.entries.where("entries.body ~* ?", "\\m#{sanitized_phrase}\\M").reorder(:date)
      else
        search = Search.new(term: search_term, user: user)
        search.entries.reorder(:date)
      end
    elsif year.present?
      start_date = Date.new(year.to_i, 1, 1)
      end_date = Date.new(year.to_i, 12, 31)
      user.entries.where(date: start_date..end_date).reorder(:date)
    else
      user.entries.reorder(:date)
    end
  end

  def build_filename(only_images, search_term, year, format)
    timestamp = Time.now.strftime('%Y-%m-%d')
    extension = format.to_s

    if only_images
      "dabble_export_image_entries_#{timestamp}.#{extension}"
    elsif search_term.present?
      "dabble_export_search_#{search_term.parameterize}_#{timestamp}.#{extension}"
    elsif year.present?
      "dabble_export_#{year}.#{extension}"
    else
      "dabble_export_#{timestamp}.#{extension}"
    end
  end

  def generate_export(tempfile, entries_scope, format, only_images)
    case format.to_s
    when 'json'
      generate_json_export(tempfile, entries_scope)
    when 'txt'
      generate_txt_export(tempfile, entries_scope, only_images)
    end
  end

  def generate_json_export(tempfile, entries_scope)
    tempfile.write("[\n")
    first = true
    entries_scope.select(:id, :user_id, :date, :body, :image).find_each(batch_size: 100) do |entry|
      tempfile.write(",\n") unless first
      first = false
      entry_hash = { date: entry.date, body: entry.body }
      entry_hash[:image] = entry.image_url_cdn(cloudflare: false) if entry.image.present?
      tempfile.write(JSON.pretty_generate(entry_hash))
    end
    tempfile.write("\n]")
  end

  def generate_txt_export(tempfile, entries_scope, only_images)
    entries_scope.select(:id, :user_id, :date, :body, :image).find_each(batch_size: 100) do |entry|
      if only_images
        tempfile.write("#{entry.image_url_cdn(cloudflare: false)}\n")
      else
        tempfile.write("## #{entry.date.strftime('%Y-%m-%d')}\n")
        tempfile.write("#{entry.text_body}\n\n")
      end
    end
  end
end
