# frozen_string_literal: true

# A journal as one web page, for the ZIP (journal.html): open it in any
# browser, no internet needed. Photos are shown from the ZIP's images/ folder.
module ExportHtml
  # What an entry's own HTML may keep. Anything that could run code, or style
  # the page around it, is dropped.
  TAGS = %w[p br div span strong b em i u a ul ol li blockquote hr img].freeze
  ATTRIBUTES = %w[href src alt].freeze

  STYLE = <<~CSS
    * { box-sizing: border-box; }
    body { margin: 0; background: #f4f4ef; color: #222; font: 18px/1.6 Georgia, "Times New Roman", serif; }
    main { max-width: 680px; margin: 0 auto; padding: 32px 16px 64px; }
    h1 { margin: 0 0 4px; font-size: 34px; font-weight: normal; }
    .subset { margin: 0 0 4px; font-size: 20px; }
    .summary { margin: 0 0 12px; color: #777; font: 14px/1.4 -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; }
    .order { display: inline-block; margin: 0 0 28px; color: #777; font: 14px/1.4 -apple-system, "Segoe UI", Helvetica, Arial, sans-serif; cursor: pointer; }
    .entries { display: flex; flex-direction: column; }
    /* Entries are written newest first; ticking the box flips them. */
    main:has(#oldest-first:checked) .entries { flex-direction: column-reverse; }
    /* A long link or run of unbroken text wraps instead of widening the page. */
    article { min-width: 0; margin: 0 0 24px; padding: 24px; background: #fff; border: 1px solid #deded6; border-radius: 8px; overflow-wrap: anywhere; }
    article h2 { margin: 0 0 16px; color: #9c1c1c; font-size: 22px; font-weight: normal; }
    article img { display: block; max-width: 100%; height: auto; border-radius: 4px; }
    article .photo { display: block; margin: 16px 0 0; }
    article a { color: #5c6652; }
    article > :last-child { margin-bottom: 0; }
  CSS

  module_function

  # description: what the page holds, such as "Entries from 2021".
  def header(entry_count, description = nil)
    subset = description.present? && description != "All entries" ? ERB::Util.html_escape(description) : nil
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{['Dabble Me journal', subset].compact.join(': ')}</title>
      <style>
      #{STYLE}</style>
      </head>
      <body>
      <main>
      <h1>Dabble Me journal</h1>
      #{%(<p class="subset">#{subset}</p>) if subset}
      <p class="summary">#{entry_count} #{entry_count == 1 ? 'entry' : 'entries'}, exported #{Time.current.strftime('%B %-d, %Y')}</p>
      <label class="order"><input type="checkbox" id="oldest-first"> Oldest first</label>
      <div class="entries">
    HTML
  end

  # image is the photo's path inside the ZIP, when there is one to show.
  # Entries are written newest first.
  def entry(entry, image: nil)
    html = +%(<article id="#{entry.date.strftime('%Y-%m-%d')}">\n)
    html << "<h2>#{entry.date.strftime('%A, %B %-d, %Y')}</h2>\n"
    html << "#{sanitizer.sanitize(entry.formatted_body, tags: TAGS, attributes: ATTRIBUTES)}\n" if entry.body.present?
    if image
      src = ERB::Util.html_escape(image)
      html << %(<a class="photo" href="#{src}" target="_blank" rel="noopener"><img src="#{src}" alt="Photo"></a>\n)
    end
    html << "</article>\n"
  end

  def footer
    "</div>\n</main>\n</body>\n</html>\n"
  end

  def sanitizer
    @sanitizer ||= Rails::HTML5::SafeListSanitizer.new
  end
end
