# frozen_string_literal: true

# A journal as one Markdown document: a title, then each entry under its date.
# ExportArchive writes it into the ZIP as journal.md; entries#export streams
# it on its own for an immediate download.
module ExportMarkdown
  BATCH_SIZE = 200

  module_function

  # description: what the document holds when it isn't the whole journal,
  # such as "Entries from 2021".
  def header(description = nil)
    text = +"# Dabble Me journal\n\n"
    text << "#{description}\n\n" if description.present? && description != "All entries"
    text
  end

  # image is the photo's path inside a ZIP, when there is one to point to.
  def entry(entry, image: nil)
    text = +"## #{entry.date.strftime('%Y-%m-%d')} (#{entry.date.strftime('%A')})\n\n"
    body = entry.body.present? ? ReverseMarkdown.convert(entry.formatted_body, unknown_tags: :bypass).to_s.strip : ""
    text << "#{body}\n\n" if body.present?
    text << "![Photo](#{image})\n\n" if image
    text
  end

  # The whole document in pieces, oldest entry first, read in batches so a
  # long journal is never all in memory.
  def stream(entries, description: nil)
    Enumerator.new do |yielder|
      yielder << header(description)
      ids = entries.unscope(:order).order(:date, :id).pluck(:id)
      ids.each_slice(BATCH_SIZE) do |slice|
        by_id = Entry.unscoped.where(id: slice).index_by(&:id)
        slice.each { |id| yielder << entry(by_id[id]) if by_id[id] }
      end
    end
  end
end
