module ApplicationHelper
  # Anthropic docs: remote MCP / custom connectors (URL + optional OAuth in UI).
  def self.claude_remote_mcp_connectors_url
    "https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp"
  end

  # Full MCP endpoint URL for docs and client config (outside a web request).
  # Host comes from the app’s primary domain env var.
  def self.mcp_server_url
    Rails.application.routes.url_helpers.mcp_url(mcp_url_options)
  end

  def self.primary_domain_env_key
    %w[MAIN DOMAIN].join("_")
  end

  def self.mcp_url_options
    host = ENV[primary_domain_env_key].presence
    return { only_path: true } if host.blank?

    if Rails.env.production?
      { protocol: "https", host: host }
    elsif host.match?(/\A[^.]+\z/)
      { protocol: "http", host: host, port: 3000 }
    else
      { protocol: "http", host: host }
    end
  end

  # Public journal site base URL (browser links), not the MCP JSON-RPC path.
  def self.site_public_base_url
    host = ENV[primary_domain_env_key].presence || "dabble.me"
    if Rails.env.production?
      "https://#{host}"
    elsif host.match?(/\A[^.]+\z/)
      "http://#{host}:3000"
    else
      "http://#{host}"
    end
  end

  def title(page_title)
    content_for(:title) { page_title.to_s }
  end

  def yield_or_default(section, default = "")
    content_for?(section) ? content_for(section) : default
  end

  # Two-letter initials for OAuth consent (e.g. "MCP Inspector" -> "MI").
  def oauth_application_initials(name)
    return "?" if name.blank?

    words = name.strip.split(/\s+/).reject(&:blank?)
    letters =
      if words.length >= 2
        [words[0][0], words[1][0]]
      else
        w = words[0]
        [w[0], w[1] || w[0]]
      end
    letters.join.upcase
  end

  def tag_relative_date(tag_date, entry_date)
    return "" unless entry_date.present?
    return "Today" if tag_date == entry_date
    return "Yesterday" if tag_date == entry_date - 1.day

    a = []
    a << distance_of_time_in_words(tag_date, entry_date)
    if tag_date > entry_date
      a << "from"
    else
      a << "since"
    end
    # a << tag_date.strftime('%b %-d, %Y')
    a << "entry"
    a.join(" ")
  end

  def distance_of_time_in_words(earlier_date, later_date)
    Jekyll::Timeago.timeago(earlier_date, later_date, depth: 2, threshold: 0.05).gsub(" ago", "").gsub("in ", "").gsub("tomorrow", "1 day")
  end

  def format_number(number)
    return number unless number.present?

    number = trim(number) if number.is_a?(String)
    rounded_number = number.to_i > 100 ? number.round(0) : number.round(2)
    number_with_delimiter(rounded_number, delimiter: ",")
  end

  def elapsed_days_in_year(year = Date.today.year)
    ref_date = @user_today || Date.today
    year.to_i == ref_date.year ? ref_date.yday : Date.new(year.to_i, 12, 31).yday
  end

  def self.faqs
    main_domain = ENV.fetch(primary_domain_env_key, "")
    routes = Rails.application.routes.url_helpers
    base = site_public_base_url
    mcp_endpoint = mcp_server_url
    claude_url = claude_remote_mcp_connectors_url
    mcp_connect_answer = <<~HTML.squish
      <p class="text-muted mb-3"><span class="font-semibold">Requirements:</span> a PRO subscription plus a passkey or two-factor authentication on
      <a href="#{routes.security_path}" class="text-accent hover:text-primary underline">Account security</a>.</p>
      <p class="text-muted mb-3">In your MCP client, add a remote MCP connector using this endpoint (Streamable HTTP, OAuth when prompted):</p>
      <p class="mb-3"><code class="text-base select-all break-all bg-olive-200 px-2 py-1 text-olive-900">#{ERB::Util.html_escape(mcp_endpoint)}</code></p>
      <p class="text-muted mb-3">Complete the browser sign-in and approve access. For connector UI details, see
      <a href="#{ERB::Util.html_escape(claude_url)}" class="text-accent hover:text-primary underline" target="_blank" rel="noopener noreferrer">Anthropic’s guide to remote MCP connectors</a>.</p>
      <p class="text-muted mb-2"><span class="font-semibold">Example prompts</span> (plain language—the client calls tools for you):</p>
      <ul class="list-disc pl-5 space-y-1.5 text-muted text-sm mb-3">
        <li><span class="font-medium text-primary">Look back:</span> “What did I write about travel last year?” or “Show entries from March with #gratitude.”</li>
        <li><span class="font-medium text-primary">Scan a range:</span> “List my entries from last month, newest first.”</li>
        <li><span class="font-medium text-primary">Patterns:</span> “How often did I journal this year? What hashtags show up most?”</li>
        <li><span class="font-medium text-primary">Log something:</span> “Add a journal note for today: …” (creates or appends that day’s entry, same rules as the web app).</li>
      </ul>
      <p class="text-muted mb-2"><span class="font-semibold">Tools behind those requests:</span>
      <code class="text-sm">search_entries</code> (keyword or phrase, optional dates),
      <code class="text-sm">list_entries</code> (date range),
      <code class="text-sm">analyze_entries</code> (counts, hashtags, volume),
      <code class="text-sm">create_entry</code> (body text and/or optional <code class="text-sm">image_url</code> / <code class="text-sm">image_base64</code>, optional date).</p>
      <p class="text-muted mb-3"><span class="font-semibold">Opening a day in the browser:</span> <code class="text-sm select-all">#{ERB::Util.html_escape(base)}/entries/YYYY/M/D</code> with <span class="font-medium">unpadded</span> month and day (example:
      <a href="#{ERB::Util.html_escape(base)}/entries/2026/4/21" class="text-accent hover:text-primary underline" target="_blank" rel="noopener noreferrer">#{ERB::Util.html_escape(base)}/entries/2026/4/21</a>).
      New web entries: <a href="#{ERB::Util.html_escape(base)}/write" class="text-accent hover:text-primary underline" target="_blank" rel="noopener noreferrer">#{ERB::Util.html_escape(base)}/write</a>.</p>
      <p class="text-muted mb-3">To disconnect an app, open
      <a href="#{routes.security_path(anchor: "connected-apps")}" class="text-accent hover:text-primary underline">Account security</a>
      and see <span class="font-semibold">Connected apps</span>.</p>
    HTML

    {
      pro_features: {
        title: "Paid Features",
        badge: "PRO",
        questions: [
          {
            q: "How do I add photos to my entry?",
            a: "When you reply to your Dabble Me email, just attach photos to the email and they'll be saved with your entry. You can also add photos on the website when you edit an entry. You can add up to 5 photos per entry (they will create a collage). Dabble Me supports JPEG, GIF, PNG, and HEIC/HEIF (mobile) formats."
          },
          {
            q: "How do I edit or delete an entry?",
            a: "When viewing the entries page, you'll see a pencil icon in the top right of each entry. Clicking that icon takes you to the edit page. There's a delete button (trash icon) on the edit page in case you'd like to delete your entry."
          },
          {
            q: "Can I write entries on the website?",
            a: "Yes! PRO members can write entries on the website for any date. Simply click \"WRITE\" at the top of the page when logged in."
          },
          {
            html_id: "mcp",
            q: "How do I connect to Dabble Me to Claude or other MCP-compatible apps?",
            a: mcp_connect_answer
          },
          {
            q: "How do I embed songs from Spotify?",
            a: "Use the \"Copy Link\" feature in Spotify and paste those links (either dropping in the full URL or as a hyperlink) to your entry and you'll see them embedded right on the web, ready to listen to. Dabble Me will also pull out the artist & song title and send those alongside your entries in your reminder emails."
          },
          {
            q: "Can I import from OhLife or other services?",
            a: "Yes! PRO members can visit the <a href='#{Rails.application.routes.url_helpers.import_path}' class='text-accent hover:text-primary underline'>Importer</a> to import entries from OhLife, Ahhlife, and Trailmix.life."
          },
          {
            q: "Can I get a refund?",
            a: "If something doesn’t feel right, email us at #{ActionController::Base.helpers.mail_to("hello@#{main_domain}", "hello@#{main_domain}", subject: "Refund Request", encode: "hex", class: "text-accent hover:text-primary underline")} within 30 days of the charge and we’ll take care of it. Refunds are handled case by case, and we always follow applicable laws."
          },
          {
            q: "What happens to my data if I cancel my subscription?",
            a: "If you downgrade to a free account, your existing entries will remain private and accessible only to you, but you will lose access to the premium features."
          }
        ]
      },
      general: {
        title: "General Questions",
        badge: nil,
        questions: [
          {
            q: "Are my entries private?",
            a: "<span class='font-semibold'>Yes, by design.</span> Your entries can’t be shared, posted, fed into AI models, or made public in any way...and they're never at risk of being indexed by search engines. There's no social layer and no audience — just your journal, kept private and secure. If you want the details, our <a href='#{Rails.application.routes.url_helpers.privacy_path}' class='text-accent hover:text-primary underline'>Privacy Policy</a> spells this out clearly."
          },
          {
            q: "Is there a mobile app?",
            a: "<span class='font-semibold'>No — and that’s intentional.</span> There’s no Dabble Me app in the App Store or Google Play. Most people write by replying to the daily email using the email app they already have on their phone. The website is fully mobile-friendly if you ever want to browse or edit entries."
          },
          {
            q: "Is this really free?",
            a: "<span class='font-semibold'>Yes. The core experience is free, forever.</span> You'll receive an email prompt every other Sunday and can reply by email to keep your journal. When you want daily prompts, photos, search, and other tools, you can upgrade to PRO for $4/month or $40/year."
          },
          {
            id: "ideas-for-writing",
            q: "What should I journal about?",
            a: "<ul class='list-disc pl-2 space-y-2 ml-3'>
            <li>
              <span class='font-semibold'>The One Framework</span>
              — if journaling feels overwhelming, start here. Every evening, write just three things: <em>1 win from the day, 1 point of tension or stress, and 1 bit of gratitude</em>. That's it. Five minutes, no pressure, and you'll start to see patterns in what lifts you up and what weighs you down. Popularized by <a href='https://www.sahilbloom.com/newsletter/the-1-1-1-method-forecasts-for-the-future-more' target='_blank' class='text-accent hover:text-primary underline'>Sahil Bloom</a>, this simple framework makes journaling finally stick.
            </li>
            <li>
              <span class='font-semibold'>Travel Log</span>
              — capture the places you go while you're still there. The name of that tiny restaurant, the street performer who made you cry, the wrong turn that led to the best view of the trip. Use #Paris or #RoadTrip2025 to group your adventures, and when the daily email resurfaces that random Tuesday in Tokyo three years later, you'll be right back on that train platform.
            </li>
            <li>
              <span class='font-semibold'>Relationship Time Capsule</span>
              — write about the people you love while the moments are fresh. The thing your partner said that made you laugh, the weird inside joke your best friend started, the look on your mom's face when you surprised her. Tag entries with #Sarah or #Dad and build a searchable archive of the people who matter most—one that will guarantee you future smiles.
            </li>
            <li>
              <span class='font-semibold'>Career Wins &amp; Lessons</span>
              — it's easy to forget what you've accomplished at work by the time performance reviews roll around. Jot down the projects you crushed, the feedback you received, the hard conversations you navigated. Tag with #Work or #Promotion, and when you need to update your resume or negotiate a raise, you'll have receipts.
            </li>
            <li>
              <span class='font-semibold'>Gratitude Before Bed</span>
              — end each day with one thing you're thankful for and tag it with #Gratitude. Over time, you'll build a searchable database of hundreds of small joys. When a tough day hits, scroll back through your gratitude entries and remember: your life is fuller than it feels right now.
            </li>
          </ul>"
          },
          {
            q: "Does this service use AI to read or analyze my entries?",
            a: "No, not by default. Dabble Me does not use AI to read or analyze your entries unless you explicitly turn on an optional feature yourself.<div class='mt-2'>If you prefer not to use AI at all, you can always export your journal and analyze it locally or in a tool you control.</div>"
          },
          {
            q: "How do I save a copy of my entries?",
            a: "You can download a copy of your entries at any time from the bottom of the <a href='#{Rails.application.routes.url_helpers.settings_path}' class='text-accent hover:text-primary underline'>settings page</a>. Export as plain text (TXT) or JSON (with rich formatting)."
          },
          {
            q: "What happens to my data if I delete my account?",
            a: "<div class='mt-2'>If you <em>delete</em> your account, all of your entries and your account data will be permanently deleted from active systems within a reasonable period, subject to backup retention and legal requirements.</div><div class='mt-2'>Delete your account <a href='#{Rails.application.routes.url_helpers.delete_account_path}' class='text-accent hover:text-primary underline'>here</a>.</div><div class='mt-2'>You can export your data at any time from the <a href='#{Rails.application.routes.url_helpers.settings_path(anchor: 'export')}' class='text-accent hover:text-primary underline'>settings page</a>.</div>"
          },
          {
            q: "I'm new and didn't get my scheduled email. How come?",
            a: "Things work differently on your first day. Instead of sending the email at your scheduled time, we send your first email right when you sign up. After your first day, you'll always get your email according to <a href='#{Rails.application.routes.url_helpers.settings_path}' class='text-accent hover:text-primary underline'>your settings</a>."
          },
          {
            q: "Can I reply to an email more than once?",
            a: "Yes! Each reply just gets added to that day's entry. Write throughout the day if you'd like."
          },
          {
            q: "How can I set the date of an entry I email in?",
            a: "If you leave the subject line blank, the date will be today's date. If you want to adjust the date, you can add a subject line with the date in the format of <code class='text-red-500 text-sm select-all'>January 2, 2024</code> and Dabble Me will use that date instead. Another acceptable format is <code class='text-red-500 text-sm select-all'>2024-12-22</code> (YYYY-MM-DD)."
          },
          {
            q: "What are \"Inspirations\"?",
            a: "Ignore them if you want; they're just little quotes or questions that might inspire you to write. Entries inspired by these prompts will be tagged with a lightbulb icon that you can hover over to see the inspiration."
          },
          {
            q: "Who built Dabble Me?",
            a: "👋 Hi! I'm <a href='https://paularterburn.com/' class='text-accent hover:text-primary underline' target='_blank'>Paul Arterburn</a>. I built and maintain Dabble Me, and I'm also the VP of Engineering at <a href='https://unreasonablegroup.com/' class='text-accent hover:text-primary underline' target='_blank'>Unreasonable Group</a> helping entrepreneurs bend history in the right direction. Previously, I was the technical co-founder of Brandfolder, a digital asset management platform powering some of the biggest brands in the world.<div class='mt-2'>I created Dabble Me primarily for myself as a way to remember and reflect on the days in a format that would actually trigger me to write — over email. Read about why and how I built Dabble Me in a blog post: <a href='https://medium.com/startup-lesson-learned/increase-your-happiness-with-daily-journaling-8109b0700506' class='text-accent hover:text-primary underline' target='_blank'>Increase Your Happiness with Daily Journaling</a>.</div><div class='mt-2'>I built Dabble Me as an experienced developer with privacy and security in mind from the start. It's not a rushed AI side project or a growth experiment. It's independently run, funded by its users for over #{Date.today.year - Date.new(2014, 9, 29).year} years, and designed to keep your journal private. No investors. No selling your data. Just a simple, trustworthy place to write. The code is also open-sourced on <a href='https://github.com/parterburn/dabble.me' class='text-accent hover:text-primary underline' target='_blank'>GitHub</a>.</div>" # pragma: allowlist secret
          }
        ]
      }
    }
  end
end
