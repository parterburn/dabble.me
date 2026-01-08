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
            id: "ideas-for-writing",
            q: "What should I journal about?",
            a: "<ul class='list-disc text-primary pl-2 space-y-2 ml-3'>
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
            a: "No. There is a private beta with built-in AI-powered features, but they are entirely opt-in and turned off by default.<div class='mt-2'>If you'd like to use AI to analyze your entries, you can easily export your full journal (or just part of it) at any time and use it with your own AI tools for analysis or reflection.</div>"
          },
          {
            q: "Is there a mobile app?",
            a: "There's no Dabble Me app in the App Store or Google Play. The website is fully mobile-friendly and works smoothly in any mobile browser. Most people write their entries by replying to the daily email using their phone's email app, like Mail or Gmail."
          },
          {
            q: "Is this really free?",
            a: "A basic, limited version of the service is free, with email prompts sent every other Sunday. For daily prompts, photos, search, calendar view, and other advanced features, you can upgrade to PRO for $4/month or $40/year."
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
            a: "If you leave the subject line blank, the date will be today's date. If you want to adjust the date, you can add a subject line with the date in the format of <code class='text-red-500 text-sm select-all'>January 2, 2024</code> and Dabble Me will use that date instead. Another acceptable format is <code class='text-red-500 text-sm select-all'>2024-12-22</code> (YYYY-MM-DD)."
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
            a: "Dabble Me is built thoughtfully, with privacy and security in mind from the start. It's not a rushed AI side project or a growth experiment. It's independently run, funded by its users for over #{Date.today.year - Date.parse('2014-09-29').year} years, and designed to keep your journal private. No investors. No selling your data. Just a simple, trustworthy place to write. The code is also open-sourced on <a href='https://github.com/parterburn/dabble.me' class='text-accent hover:text-primary underline' target='_blank'>GitHub</a>."
          }
        ]
      }
    }
  end
end
