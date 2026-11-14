module ApplicationHelper
  def self.claude_plugin_directory_url
    "https://claude.ai/customize/plugins/id/6b2f67b8-6341-42d1-a2f1-d63df3107efe%40anthropic-plugin-directory"
  end

  # The iOS app's public beta (TestFlight), until it's in the App Store.
  def self.ios_testflight_url
    "https://testflight.apple.com/join/mYj4vrFZ"
  end

  def self.chatgpt_plugin_directory_url
    "https://chatgpt.com/plugins/plugin_asdk_app_6ac8451cdf78819190a3a26f21bfe561"
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

  # Known third-party apps shown with brand logos on the OAuth consent screen.
  # Brand logos are only shown when all redirect URIs for the client resolve to
  # the vendor's verified domain(s), preventing DCR brand impersonation.
  OAUTH_KNOWN_APPLICATION_LOGOS = [
    {
      pattern: /\bnotion\b/i,
      verified_domains: %w[notion.so notion.com makenotion.com],
      asset: "oauth/notion.png",
      alt: "Notion",
      fit: :contain
    },
    {
      pattern: /\b(claude|anthropic)\b/i,
      verified_domains: %w[claude.ai claude.com anthropic.com],
      asset: "oauth/anthropic.png",
      alt: "Claude",
      fit: :cover
    },
    {
      pattern: /\b(chatgpt|chat\s*gpt|openai|codex)\b/i,
      verified_domains: %w[chatgpt.com openai.com],
      asset: "oauth/openai.png",
      alt: "ChatGPT",
      fit: :contain
    }
  ].freeze

  # Brand logo metadata for major OAuth clients, or nil for letter initials.
  # Requires both the client name AND all registered/requested redirect URI hosts
  # to match the brand's verified_domains.
  # Returns nil when the image is missing from the asset pipeline so a broken
  # logo can never block the consent screen.
  def oauth_application_logo(client_or_name, redirect_uri: nil)
    name = client_or_name.respond_to?(:name) ? client_or_name.name.to_s : client_or_name.to_s
    return nil if name.blank?

    logo = OAUTH_KNOWN_APPLICATION_LOGOS.find { |candidate| name.match?(candidate[:pattern]) }
    return nil if logo.blank?

    uris = extract_oauth_redirect_uris(client_or_name, redirect_uri)
    return nil if uris.empty? || !uris.all? { |u| oauth_uri_matches_domains?(u, logo[:verified_domains]) }

    begin
      logo.merge(src: image_path(logo[:asset]))
    rescue Sprockets::Rails::Helper::AssetNotFound, Sprockets::Rails::Helper::AssetNotPrecompiled => e
      Sentry.capture_exception(e)
      nil
    end
  end

  def oauth_redirect_host(redirect_uri)
    uri = URI.parse(redirect_uri.to_s.strip)
    uri.host.presence
  rescue URI::InvalidURIError
    nil
  end

  def extract_oauth_redirect_uris(client_or_name, redirect_uri)
    app_uris =
      if client_or_name.respond_to?(:application) && client_or_name.application.respond_to?(:redirect_uri)
        client_or_name.application.redirect_uri.to_s.split
      elsif client_or_name.respond_to?(:redirect_uri)
        client_or_name.redirect_uri.to_s.split
      else
        []
      end
    (app_uris + Array(redirect_uri).flat_map { |u| u.to_s.split }).map(&:strip).reject(&:blank?).uniq
  end

  def oauth_uri_matches_domains?(raw_uri, verified_domains)
    uri = URI.parse(raw_uri.to_s)
    return false unless uri.scheme.to_s.downcase == "https"

    host = uri.host.to_s.downcase.sub(/\.\z/, "")
    return false if host.blank?

    Array(verified_domains).any? do |domain|
      d = domain.to_s.downcase
      host == d || host.end_with?(".#{d}")
    end
  rescue URI::InvalidURIError
    false
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
    link = "text-accent hover:text-primary underline"
    # In plain words: the endpoint, sign-in details and tool names are on the technical reference.
    mcp_connect_answer = <<~HTML.squish
      <p class="text-muted mb-3">Dabble Me works with the AI assistant you already use. Once it's connected, you can ask
      Claude or ChatGPT about your past entries, or have it save a new one for you.</p>
      <ul class="list-disc pl-5 space-y-1.5 text-muted mb-3">
        <li><span class="font-medium text-primary">Claude:</span>
        <a href="#{ERB::Util.html_escape(claude_plugin_directory_url)}" class="#{link}" target="_blank" rel="noopener noreferrer">add the Dabble Me plugin for Claude</a>.</li>
        <li><span class="font-medium text-primary">ChatGPT:</span>
        <a href="#{ERB::Util.html_escape(chatgpt_plugin_directory_url)}" class="#{link}" target="_blank" rel="noopener noreferrer">add the Dabble Me app for ChatGPT</a>.</li>
      </ul>
      <p class="text-muted mb-3">Then sign in to Dabble Me when it asks, and approve the connection. That's all there is to set up.
      You'll need a <span class="font-semibold">PRO subscription</span>.</p>
      <p class="text-muted mb-2"><span class="font-semibold">Things to ask</span>, in your own words:</p>
      <ul class="list-disc pl-5 space-y-1.5 text-muted text-sm mb-3">
        <li><span class="font-medium text-primary">Look back:</span> “What did I write about travel last year?” or “Show me March's entries with #gratitude.”</li>
        <li><span class="font-medium text-primary">Catch up:</span> “Summarize what I wrote last month.”</li>
        <li><span class="font-medium text-primary">See patterns:</span> “How often did I journal this year? Which hashtags come up most?”</li>
        <li><span class="font-medium text-primary">Write:</span> “Add this to today's journal: …” (it adds to today's entry if you've already written one).</li>
      </ul>
      <p class="text-muted mb-3">To disconnect an assistant, open
      <a href="#{routes.security_path(anchor: "connected-apps")}" class="#{link}">Account security</a>
      and remove it under <span class="font-semibold">Connected apps</span>. It loses access right away.</p>
      <p class="text-muted mb-3">More about how it works and what's shared is in the
      <a href="#{routes.mcp_server_docs_path}" class="#{link}">AI Connector guide</a>. Using a different AI app, or building something? See the
      <a href="#{routes.mcp_server_developer_docs_path}" class="#{link}">technical reference</a>.</p>
    HTML

    {
      pro_features: {
        title: "Paid Features",
        badge: "PRO",
        questions: [
          {
            q: "How do I add photos to my entry?",
            a: "When you reply to your Dabble Me email, just attach photos to the email and they'll be saved with your entry. You can also add photos on the website when you edit an entry. You can add up to #{CollageGenerator::MAX_IMAGES} photos per entry (they will create a collage). Dabble Me supports JPEG, GIF, PNG, and HEIC/HEIF (mobile) formats."
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
            q: "How do I connect Dabble Me to Claude or ChatGPT?",
            a: mcp_connect_answer
          },
          {
            q: "How do I embed songs from Spotify?",
            a: "Use the \"Copy Link\" feature in Spotify and paste those links (either dropping in the full URL or as a hyperlink) to your entry and you'll see them embedded right on the web, ready to listen to. Dabble Me will also pull out the artist & song title and send those alongside your entries in your reminder emails."
          },
          {
            q: "Can I import from OhLife or other services?",
            a: "Yes! PRO members can visit <a href='#{Rails.application.routes.url_helpers.import_path}' class='text-accent hover:text-primary underline'>Import Entries</a> to bring in entries from Day One, OhLife, Ahhlife, and Trailmix.life."
          },
          {
            q: "How do I export my entries?",
            a: "Visit <a href='#{Rails.application.routes.url_helpers.export_entries_path}' class='text-accent hover:text-primary underline'>Export Entries</a>, under your account menu. You can export everything or one year, as a ZIP with your journal as a web page, Markdown and JSON plus your photos, or as a single Markdown file. Exporting is free on every plan."
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
            a: "<span class='font-semibold'>Yes, for iPhone and iPad, in beta.</span> Dabble Me for iOS is available now through Apple's TestFlight: <a href='#{ios_testflight_url}' class='text-accent hover:text-primary underline' target='_blank' rel='noopener noreferrer'>join the beta to install it</a>. Read your journal, write new entries, and get a daily reminder; photos, editing, search and On This Day are part of PRO.<div class='mt-2'>There's no Android app yet. On any phone you can still write by replying to the daily email from your mail app, and the website works well on a small screen. PRO members can also <a href='#{routes.mcp_server_docs_path}' class='text-accent hover:text-primary underline'>connect Dabble Me to Claude or ChatGPT</a> and journal from those apps, by voice if you like.</div>"
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
            a: "<div class='mt-2'>If you <em>delete</em> your account, all of your entries and your account data will be permanently deleted from active systems within a reasonable period, subject to backup retention and legal requirements.</div><div class='mt-2'>Delete your account <a href='#{Rails.application.routes.url_helpers.delete_account_path}' class='text-accent hover:text-primary underline'>here</a>.</div><div class='mt-2'>You can export your data at any time from the <a href='#{Rails.application.routes.url_helpers.export_entries_path}' class='text-accent hover:text-primary underline'>Export Entries</a> page.</div>"
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
