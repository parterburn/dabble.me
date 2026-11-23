module ApplicationHelper
  LAUNCH_DATE = Date.new(2014, 9, 29)

  # Whole years since Dabble Me launched (Sept 29, 2014), e.g. 12 until Sept 29, 2027.
  def self.years_running(today = Date.current)
    years = today.year - LAUNCH_DATE.year
    years -= 1 if today < LAUNCH_DATE.next_year(years)
    years
  end

  def years_running
    ApplicationHelper.years_running
  end

  def self.claude_plugin_directory_url
    "https://claude.ai/customize/plugins/id/6b2f67b8-6341-42d1-a2f1-d63df3107efe%40anthropic-plugin-directory"
  end

  # The iOS app's beta (TestFlight), until it's in the App Store. Only PRO members are sent it
  # (the web footer, the empty journal, the thank-you email): a TestFlight purchase is free.
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

  # The short list on the homepage. /support keeps the full answers.
  def self.home_faqs
    routes = Rails.application.routes.url_helpers
    link = "text-accent hover:text-primary underline"
    [
      {
        q: "Are my entries really private?",
        a: "Yes, by design. There’s no social feed, no ads, no tracking, no data selling, and no search-engine indexing, and your entries are never used to train AI. The iPhone app supports Face ID, hides your journal in the app switcher, and strips location data from photos before upload. On-device Apple Intelligence never sends your journal anywhere, and the optional Claude and ChatGPT connections stay off unless you approve them. <a href='#{routes.privacy_path}' class='#{link}'>Read the privacy policy</a>."
      },
      {
        q: "How do I write entries?",
        a: "However feels easiest that day. Open the <a href='#{routes.journal_app_path}' class='#{link}'>iPhone &amp; iPad app</a> (or tap a Lock Screen widget), or reply to a prompt email from any device. With PRO, you can also write on the web, or talk out an entry through <a href='#{routes.mcp_server_docs_path}' class='#{link}'>Claude or ChatGPT</a>."
      },
      {
        q: "Is this really free?",
        a: "Yes, forever. Free accounts can read and write entries, get a daily reminder in the iPhone app, on-device Apple Intelligence reflections and prompts, an email prompt every other Sunday, and full data export. <a href='#{routes.subscribe_path}' class='#{link}'>Upgrade to PRO</a> ($4/month or $40/year) for custom email schedules, photos, editing, search, stats, On This Day, Year in Review, and AI connectors."
      },
      {
        q: "What should I write about?",
        a: "A few lines about your day is plenty. If you’re stuck, the app can show a gentle prompt or what was on your calendar that day. Or try 1 win, 1 thing on your mind, and 1 moment of gratitude. <a href='#{routes.how_to_start_journaling_path(anchor: "journaling-frameworks")}' class='#{link}'>See 5 simple journaling frameworks →</a>"
      }
    ]
  end

  # An FAQ answer as plain text, for the "Copy these FAQs" text and the FAQPage structured data:
  # block tags become spaces so list items don't run together, and entities are decoded.
  def self.faq_plain_text(html)
    spaced = html.to_s.gsub(%r{<(?:/?(?:li|ul|ol|div|p)|br)\b[^>]*>}i, " ")
    CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(spaced)).squish
  end

  # One FAQ by its id, from whichever section holds it.
  def self.faq(id)
    faqs.values.flat_map { |section| section[:questions] }.find { |qa| qa[:id] == id }
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
      getting_started: {
        title: "Getting Started & Ways to Write",
        badge: nil,
        html_id: "getting-started",
        questions: [
          {
            q: "Is this really free?",
            a: "<span class='font-semibold'>Yes. The core experience is free, forever.</span> Free accounts can read, write and delete entries, set a daily reminder in the iPhone app (skipped once you've written), get on-device Apple Intelligence reflections, prompts and hashtag suggestions, receive an email prompt every other Sunday, and export their data anytime. When you want custom email schedules, photos, links, editing, search, stats, On This Day, Year in Review, imports, or Claude and ChatGPT connections, you can <a href='#{routes.subscribe_path}' class='#{link}'>upgrade to PRO</a> for $4/month or $40/year."
          },
          {
            q: "Is there a mobile app?",
            a: "<span class='font-semibold'>For iPhone and iPad, coming soon to the App Store.</span> <a href='#{routes.journal_app_path}' class='#{link}'>See what the app does</a>. PRO members can try the beta now. Write with your own daily template, Home Screen and Lock Screen widgets, prompts from your calendar, and a daily nudge that skips itself once you've written. Photos, editing, search and On This Day are part of PRO.<div class='mt-2'>There's no Android app yet. On any phone you can still write by replying to the daily email from your mail app, and the website works well on a small screen. PRO members can also <a href='#{routes.mcp_server_docs_path}' class='#{link}'>connect Dabble Me to Claude or ChatGPT</a> and journal from those apps, by voice if you like. If you'd like an Android app, email #{ActionController::Base.helpers.mail_to("hello@#{main_domain}", "hello@#{main_domain}", subject: "Android app", class: link)} and let us know.</div>"
          },
          {
            q: "How is Dabble Me different from Apple's Journal app?",
            a: "<span class='font-semibold'>Apple's Journal reminds you to open an app. Dabble Me puts the prompt in your inbox.</span> Each one comes with one of your past entries, and you write by hitting reply. Your journal also lives on the web and works by email, so it isn't tied to one phone or your Apple ID. You can <a href='#{routes.mcp_server_docs_path}' class='#{link}'>connect it to Claude or ChatGPT</a> to ask about your past entries, export everything as a ZIP or Markdown, and it's been running independently for #{years_running} years.<div class='mt-2'>To be fair to Apple: Journal is free, built into your iPhone, and end-to-end encrypted. Dabble Me encrypts your entries on our servers with keys kept separately, but it isn't end-to-end encrypted, because our servers have to read your entries to email you past ones, save the replies you send, show and search your journal on the web, and let an AI assistant you connect look through it. See the <a href='#{routes.privacy_path}' class='#{link}'>Privacy Policy</a> for details.</div>"
          },
          {
            id: "ideas-for-writing",
            q: "What should I journal about?",
            a: "<ul class='list-disc pl-2 space-y-2 ml-3'>
            <li>
              <span class='font-semibold!'>The One Framework</span>
              — if journaling feels overwhelming, start here. Every evening, write just three things: <em>1 win from the day, 1 point of tension or stress, and 1 bit of gratitude</em>. That's it. Five minutes, no pressure, and you'll start to see patterns in what lifts you up and what weighs you down. Popularized by <a href='https://www.sahilbloom.com/newsletter/the-1-1-1-method-forecasts-for-the-future-more' target='_blank' class='text-accent hover:text-primary underline'>Sahil Bloom</a>, this simple framework makes journaling finally stick.
            </li>
            <li>
              <span class='font-semibold!'>Travel Log</span>
              — capture the places you go while you're still there. The name of that tiny restaurant, the street performer who made you cry, the wrong turn that led to the best view of the trip. Use #Paris or #RoadTrip2025 to group your adventures, and when the daily email resurfaces that random Tuesday in Tokyo three years later, you'll be right back on that train platform.
            </li>
            <li>
              <span class='font-semibold!'>Relationship Time Capsule</span>
              — write about the people you love while the moments are fresh. The thing your partner said that made you laugh, the weird inside joke your best friend started, the look on your mom's face when you surprised her. Tag entries with #Sarah or #Dad and build a searchable archive of the people who matter most—one that will guarantee you future smiles.
            </li>
            <li>
              <span class='font-semibold!'>Career Wins &amp; Lessons</span>
              — it's easy to forget what you've accomplished at work by the time performance reviews roll around. Jot down the projects you crushed, the feedback you received, the hard conversations you navigated. Tag with #Work or #Promotion, and when you need to update your resume or negotiate a raise, you'll have receipts.
            </li>
            <li>
              <span class='font-semibold!'>Gratitude Before Bed</span>
              — end each day with one thing you're thankful for and tag it with #Gratitude. Over time, you'll build a searchable database of hundreds of small joys. When a tough day hits, scroll back through your gratitude entries and remember: your life is fuller than it feels right now.
            </li>
          </ul>
          <div class='mt-3'>New to journaling? <a href='#{routes.how_to_start_journaling_path}' class='#{link}'>Here's how to start</a>, or try one of <a href='#{routes.how_to_start_journaling_path(anchor: "journaling-frameworks")}' class='#{link}'>5 simple journaling frameworks</a>.</div>"
          },
          {
            q: "I'm new and didn't get my scheduled email. How come?",
            a: "Your first day works a little differently. Instead of waiting for your scheduled time, we send your first prompt right when you sign up, so you can start right away. After that, emails arrive on the schedule in <a href='#{routes.settings_path}' class='#{link}'>your settings</a>."
          },
          {
            q: "Can I reply to an email more than once?",
            a: "Yes. Every reply is added to that day's entry, so you can jot things down throughout the day."
          },
          {
            q: "How can I set the date of an entry I email in?",
            a: "Leave the subject line blank to save it under today's date. To file it under a different day, put the date in the subject line, as <code class='text-red-500 text-sm select-all'>January 2, 2024</code> or <code class='text-red-500 text-sm select-all'>2024-12-22</code> (YYYY-MM-DD)."
          },
          {
            q: "What are \"Inspirations\"?",
            a: "Little quotes or questions in your prompt emails, there to spark an idea when you're not sure what to write. Ignore them anytime. An entry written in reply to one gets a lightbulb icon you can hover over to see what inspired it."
          }
        ]
      },
      privacy: {
        title: "Privacy, AI & Your Data",
        badge: nil,
        html_id: "privacy",
        questions: [
          {
            q: "Are my entries private?",
            a: "<span class='font-semibold'>Yes, by design.</span> Your entries are encrypted on our servers, and they can’t be shared, posted, or made public in any way. They’re never used to train AI models, and they're never at risk of being indexed by search engines. There's no social feed, no ads, and no data selling. You can sign in with a passkey, a password or a two-factor code, and the iPhone app supports Face ID, hides your journal in the app switcher, and strips location data from photos before upload. Our <a href='#{routes.privacy_path}' class='#{link}'>Privacy Policy</a> spells out the details, including the site analytics we use."
          },
          {
            q: "Does this service use AI to read or analyze my entries?",
            a: "<span class='font-semibold'>Your entries are never used to train AI models.</span><ul class='list-disc pl-5 space-y-1.5 mt-2'><li><span class='font-medium text-primary'>Apple Intelligence (free, on your device):</span> on supported iPhones and iPads, the app offers reflections, daily prompts from your recent days, and hashtag suggestions. It all runs on the device, so your journal isn't sent anywhere for it, and a reflection chat is never saved unless you add it to your entry.</li><li><span class='font-medium text-primary'>Claude and ChatGPT (optional, PRO):</span> nothing connects unless you approve it, and you can <a href='#{routes.mcp_server_docs_path}' class='#{link}'>remove access</a> any time.</li></ul><div class='mt-2'>If you prefer no AI at all, ignore these features, or export your journal and analyze it locally in a tool you control.</div>"
          },
          {
            q: "How do I export my entries?",
            a: "Visit <a href='#{routes.export_entries_path}' class='#{link}'>Export Entries</a>, under your account menu. Export everything or one year as a ZIP: a full backup of your entries and photos that you can browse offline. Or export a single Markdown file, easy to bring into other apps and AI assistants. Exporting is free on every plan."
          },
          {
            q: "What happens to my data if I cancel PRO?",
            a: "Your account moves to the free plan. All of your entries stay private and readable, and you can still export everything anytime. You just lose the PRO features."
          },
          {
            q: "What happens to my data if I delete my account?",
            a: "Deleting your account permanently removes all of your entries and account data from active systems within a reasonable period, subject to backup retention and legal requirements. If you want a copy, <a href='#{routes.export_entries_path}' class='#{link}'>export your entries</a> first.<div class='mt-2'><a href='#{routes.delete_account_path}' class='#{link}'>Delete your account</a></div>"
          },
          {
            q: "Who built Dabble Me?",
            a: "👋 Hi! I'm <a href='https://paularterburn.com/' class='#{link}' target='_blank' rel='noopener noreferrer'>Paul Arterburn</a>. I built and maintain Dabble Me. I've also been Chief Technology Officer at <a href='https://unreasonablegroup.com/' class='#{link}' target='_blank' rel='noopener noreferrer'>Unreasonable Group</a> since 2016, a fellowship of growth-stage entrepreneurs scaling companies that bake impact into their profit model. Previously, I was the technical co-founder of Brandfolder, a digital asset management platform powering some of the biggest brands in the world.<div class='mt-2'>I created Dabble Me over #{years_running} years ago, for myself: I wanted the clarity of daily reflection in a format that would actually get me to write, over email, without another complicated app to maintain. Read more in <a href='https://medium.com/startup-lesson-learned/increase-your-happiness-with-daily-journaling-8109b0700506' class='#{link}' target='_blank' rel='noopener noreferrer'>Increase Your Happiness with Daily Journaling</a>.</div><div class='mt-2'>Dabble Me isn't a venture-backed growth experiment or a rushed AI side project. It's independently run with a contingency plan in place, funded entirely by paying users, and built with privacy and security from day one. No investors. No selling your data. The code is also open source on <a href='https://github.com/parterburn/dabble.me' class='#{link}' target='_blank' rel='noopener noreferrer'>GitHub</a>.</div>" # pragma: allowlist secret
          }
        ]
      },
      pro_features: {
        title: "PRO Features & Billing",
        badge: "PRO",
        questions: [
          {
            q: "How do I add photos to my entry?",
            a: "Add up to #{CollageGenerator::MAX_IMAGES} photos per entry (several become a collage). Attach them to your reply to a Dabble Me email, add them in the iPhone app, or upload them when you edit an entry on the web. JPEG, GIF, PNG and HEIC/HEIF all work, and the iPhone app strips location data before upload. Photos are part of <a href='#{routes.subscribe_path}' class='#{link}'>PRO</a>."
          },
          {
            q: "How do I write or edit entries on the web?",
            a: "<a href='#{routes.subscribe_path}' class='#{link}'>PRO members</a> can write an entry for any date by clicking \"WRITE\" at the top of the page when signed in, with rich text and clickable links. To edit an entry, click the pencil icon at its top right; the delete button (trash icon) is on the edit page. In the iPhone app, touch and hold an entry to edit its words, photos, or date."
          },
          {
            q: "How do On This Day, Year in Review and #hashtag dates work?",
            a: "<ul class='list-disc pl-5 space-y-1.5'><li><span class='font-medium text-primary'>On This Day:</span> see what you wrote on today's date in past years, on the web and on the app's Today screen.</li><li><span class='font-medium text-primary'>Year in Review:</span> from November through January, the app's Stats look back on your year: your biggest month, the people and places you wrote about, your photos and your songs.</li><li><span class='font-medium text-primary'>#hashtag dates:</span> in <a href='#{routes.settings_path}' class='#{link}'>your settings</a>, give a #hashtag a date, like a birthday or anniversary, and every matching entry shows how old someone was or how long it had been.</li></ul><div class='mt-2'>On every plan, your prompt emails bring back a past entry, and in the app you can shake your phone for a random memory.</div>"
          },
          {
            html_id: "mcp",
            q: "How do I connect Dabble Me to Claude or ChatGPT?",
            a: mcp_connect_answer
          },
          {
            q: "How do I embed songs from Spotify?",
            a: "Copy a track link in Spotify and paste it into your entry, as the full URL or as a link. Dabble Me embeds the track so you can play it right on the web, and includes the artist and song title when that entry comes back in your reminder emails."
          },
          {
            q: "Can I import from Day One, OhLife or other services?",
            a: "Yes! PRO members can visit <a href='#{routes.import_path}' class='#{link}'>Import Entries</a> to bring in entries from Day One, OhLife, Ahhlife, and Trailmix.life. Coming from one of those? See how Dabble Me compares as an <a href='#{routes.ohlife_alternative_path}' class='#{link}'>OhLife alternative</a> or a <a href='#{routes.day_one_alternative_path}' class='#{link}'>Day One alternative</a>."
          },
          {
            q: "Can I get a refund?",
            a: "If something doesn’t feel right, email us at #{ActionController::Base.helpers.mail_to("hello@#{main_domain}", "hello@#{main_domain}", subject: "Refund Request", encode: "hex", class: link)} within 30 days of a charge made on dabble.me and we’ll take care of it. Refunds are handled case by case, and we always follow applicable laws.<div class='mt-2'>If you subscribed in the iPhone app, Apple handles the billing, so refunds go through Apple: <a href='https://reportaproblem.apple.com' class='#{link}' target='_blank' rel='noopener noreferrer'>reportaproblem.apple.com</a>.</div>"
          }
        ]
      }
    }
  end
end
