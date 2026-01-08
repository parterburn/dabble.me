module ApplicationHelper
  def title(page_title)
    content_for(:title) { page_title.to_s }
  end

  def yield_or_default(section, default = '')
    content_for?(section) ? content_for(section) : default
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
            q: "How do I embed songs from Spotify?",
            a: "Use the \"Copy Link\" feature in Spotify and paste those links (either dropping in the full URL or as a hyperlink) to your entry and you'll see them embedded right on the web, ready to listen to. Dabble Me will also pull out the artist & song title and send those alongside your entries in your reminder emails."
          },
          {
            q: "Can I import from OhLife or other services?",
            a: "Yes! PRO members can visit the <a href='#{Rails.application.routes.url_helpers.import_path}' class='text-accent hover:text-primary underline'>Importer</a> to import entries from OhLife, Ahhlife, and Trailmix.life."
          }
        ]
      },
      general: {
        title: "General Questions",
        badge: nil,
        questions: [
          {
            q: "Is this really free?",
            a: "The basic service is free, with email prompts sent every other Sunday. For daily prompts, photos, search, calendar view, and other advanced features, you can upgrade to PRO for $4/month or $40/year."
          },
          {
            q: "Is there a mobile app?",
            a: "There's no Dabble Me app in the App Store or Google Play. The website is fully mobile-friendly and works smoothly in any mobile browser. Most people write their entries by replying to the daily email using their phone’s email app, like Mail or Gmail."
          },
          {
            q: "Does this service use AI to read or analyze my entries?",
            a: "No. There is a private beta with built-in AI-powered features, but they are entirely opt-in and turned off by default. If you prefer, you can export your full journal at any time and use it with your own AI tools for analysis or reflection."
          },
          {
            id: "ideas-for-writing",
            q: "Can you give me some ideas on what to write about?",
            a: "<ul class='list-disc list-inside text-primary pl-3 mb-4 space-y-2'>
            <li>
                <strong>Daily Dabble</strong>
                — reflections from your day is the most popular use case of any journal. This can be a scary one to get started with. If self-reflection is overwhelming to even think about, keep reading.
            </li>
            <li>
              <strong>Memory keeper for major events/milestones</strong>
                — we easily forget. Write it down now and the daily emails will bring you smiles when it reminds you of all your favorite moments. Take 5 minutes to write about all of the dates you go on...you never know when it might be some of the most important moments you'll be reflecting on your future spouse 😁.
            </li>
            <li>
              <strong>Goals/Health Tracking</strong>
              — use #hashtags in your posts for easily tagging entries with your different goals or visits to different doctors.
            </li>
            <li>
              <strong>Learning Aid</strong>
              — especially for learning to code or different college courses. The concept of past entries in your inbox is a way of reminding you what you learned that day. It makes the subject matter much more sticky so you actually remember it.
            </li>
            <li>
              <strong>Baby’s Firsts</strong>
              — use it to track the progress of your children. Pictures go great with this one. Jot down notes and add photos so you can easily put together a scrapbook later.
            </li>
          </ul>"
          },
          {
            q: "How do I save a copy of my entries?",
            a: "You can download a copy of your entries at any time from the bottom of the <a href='#{Rails.application.routes.url_helpers.settings_path}' class='text-accent hover:text-primary underline'>settings page</a>. Export as plain text (TXT) or JSON (with rich formatting)."
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
            a: "If you leave the subject line blank, the date will be today's date. If you want to adjust the date, you can add a subject line with the date in the format of \"January 2, 2024\" and Dabble Me will use that date instead. Another acceptable format is \"2024-12-22\" (YYYY-MM-DD)."
          },
          {
            q: "What are \"Inspirations\"?",
            a: "Ignore them if you want; they're just little quotes or questions that might inspire you to write. Entries inspired by these prompts will be tagged with a lightbulb icon that you can hover over to see the inspiration."
          },
          {
            q: "Are my entries private?",
            a: "Yes. We're trying to keep Dabble Me as similar to a real journal as possible, so there's no way to share your entries (no way to email them, no way to post them to social media, etc.) and they aren't searchable by search engines. View <a href='#{Rails.application.routes.url_helpers.privacy_path}' class='text-accent hover:text-primary underline'>our privacy policy</a> for more details."
          },
          {
            q: "Who created this?",
            a: "This service is created and maintained by <a href='https://paularterburn.com/' class='text-accent hover:text-primary underline' target='_blank'>Paul Arterburn</a>, who is also the VP of Engineering at <a href='https://unreasonablegroup.com/' class='text-accent hover:text-primary underline' target='_blank'>Unreasonable Group</a> helping entrepreneurs bend history in the right direction. Previously, Paul was the technical co-founder of <a href='https://brandfolder.com/' class='text-accent hover:text-primary underline' target='_blank'>Brandfolder</a>, a digital asset management platform powering some of the biggest brands in the world.<div class='mt-2'>Paul created Dabble Me for himself as a way to remember and reflect on the days in a format that would actually trigger him to write — over email. Read about why and how he built Dabble Me in a blog post: <a href='https://medium.com/startup-lesson-learned/increase-your-happiness-with-daily-journaling-8109b0700506' class='text-accent hover:text-primary underline' target='_blank'>Increase Your Happiness with Daily Journaling</a>.</div>"
          },
          {
            q: "Can I trust this service?",
            a: "Dabble Me is built thoughtfully, with privacy and security in mind from the start. It’s not a rushed AI side project or a growth experiment. It’s independently run, funded by its users for over #{Date.today.year - Date.parse('2014-09-29').year} years, and designed to keep your journal private. No investors. No selling your data. Just a simple, trustworthy place to write. The code is also open-sourced on <a href='https://github.com/parterburn/dabble.me' class='text-accent hover:text-primary underline' target='_blank'>GitHub</a>."
          }
        ]
      }
    }
  end
end
