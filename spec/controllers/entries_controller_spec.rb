require 'rails_helper'

RSpec.describe EntriesController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    entry
    not_my_entry
  end

  describe 'index' do
    it 'should redirect to sign in if not logged in' do
      get :index
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should show entries' do
      sign_in user
      get :index
      expect(response.status).to eq 200
      expect(response.body).to have_content(entry.formatted_body)
      expect(response.body).not_to have_content(not_my_entry.formatted_body)
    end

    it 'should clamp per page to a sane maximum' do
      sign_in user
      get :index, params: { per: 500 }
      expect(response.status).to eq 200
      expect(controller.send(:index_per_page)).to eq 50
    end

    it 'ignores a nested per param instead of erroring' do
      sign_in user
      get :index, params: { per: { nested: '1' } }
      expect(response.status).to eq 200
      expect(controller.send(:index_per_page)).to eq Kaminari.config.default_per_page
    end

    it 'rejects a nested group param instead of erroring' do
      sign_in user
      get :index, params: { group: { nested: '1' } }
      expect(response).to redirect_to(entries_path)
      expect(flash[:alert]).to eq('Invalid date format')
    end

    it 'rejects a multi-line subgroup instead of interpolating it into SQL' do
      sign_in user
      get :index, params: { group: 'emotion', subgroup: "2020\n' OR '1'='1" }
      expect(response).to redirect_to(entries_path)
      expect(flash[:alert]).to eq('Invalid date format')
    end
  end

  describe 'reflection' do
    include_context 'reflections configured'

    let(:claude_url) { ReflectionHelpers::CLAUDE_MESSAGES_URL }
    let(:ai_entry) { FactoryBot.create(:entry, user: paid_user_ai, body: '<p>Ran my first mile today.</p>', date: 2.days.ago) }

    it 'is not available without AI enabled' do
      sign_in user
      post :reflection, params: { id: entry.id }
      expect(response).to have_http_status(:forbidden)
      expect(WebMock).not_to have_requested(:post, claude_url)
    end

    it "won't reflect on someone else's entry" do
      sign_in paid_user_ai
      post :reflection, params: { id: entry.id }
      expect(response).to redirect_to(entries_path)
      expect(WebMock).not_to have_requested(:post, claude_url)
    end

    it 'is off when no reflection model is set' do
      ENV['REFLECTION_MODEL'] = nil
      sign_in paid_user_ai
      post :reflection, params: { id: ai_entry.id }
      expect(response).to have_http_status(:service_unavailable)
      expect(WebMock).not_to have_requested(:post, claude_url)
    end

    it 'returns the reflection as sanitized HTML and leaves the entry alone' do
      sign_in paid_user_ai
      stub_claude("That's a milestone.\n\n**What made today the day it clicked?** <script>alert(1)</script>")

      expect { post :reflection, params: { id: ai_entry.id } }.not_to(change { ai_entry.reload.body })

      expect(response).to have_http_status(:ok)
      html = JSON.parse(response.body)['html']
      expect(html).to include('<strong>What made today the day it clicked?</strong>')
      expect(html).not_to include('<script')
      body = claude_request_body
      expect(body['model']).to eq('claude-opus-5-5')
      expect(body).not_to have_key('tools')
      expect(claude_message_texts(body).last).to include('Ran my first mile today.')
    end

    it 'says so when Claude fails, without retrying' do
      sign_in paid_user_ai
      allow(Sentry).to receive(:capture_exception)
      stub_claude('', status: 529)

      post :reflection, params: { id: ai_entry.id }

      expect(response).to have_http_status(:bad_gateway)
      expect(JSON.parse(response.body)['error']).to eq("The AI service didn't respond. Try again in a minute.")
      expect(Sentry).to have_received(:capture_exception).with(kind_of(RubyLLM::Error), level: :info)
      expect(WebMock).to have_requested(:post, claude_url).once
    end
  end

  describe 'show' do
    before { sign_in user }

    it 'shows an entry stored at a non-midnight datetime for that calendar day' do
      entry.update_columns(date: Time.utc(2026, 7, 17, 15, 30, 0), body: '<p>UniqueShowBody999</p>')

      get :show, params: { year: 2026, month: 7, day: 17 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('UniqueShowBody999')
      expect(flash[:alert]).to be_blank
    end

    it 'shows a timezone beginning-of-day entry for that calendar day' do
      tz = ActiveSupport::TimeZone[user.send_timezone]
      day = Date.new(2026, 7, 17)
      entry.update_columns(
        date: tz.local(day.year, day.month, day.day).beginning_of_day,
        body: '<p>McpStyleShowBody</p>'
      )

      get :show, params: { year: 2026, month: 7, day: 17 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('McpStyleShowBody')
    end

    it "links #tags in a PRO user's entry to search, but not a free user's" do
      paid_entry.update_columns(date: Time.utc(2026, 11, 10), body: '<p>#Leo showered and made eggs.</p>')
      entry.update_columns(date: Time.utc(2026, 11, 10), body: '<p>#Leo showered and made eggs.</p>')

      sign_in paid_user
      get :show, params: { year: 2026, month: 11, day: 10 }
      expect(Capybara.string(response.body)).to have_css('.s-scrollable a.s-entry-hashtag[href="/search?search%5Bterm%5D=%23Leo"]', text: '#Leo')

      sign_in user
      get :show, params: { year: 2026, month: 11, day: 10 }
      expect(response.body).to include('#Leo showered')
      expect(response.body).not_to include('s-entry-hashtag')
    end

    it 'redirects with Entry not found when no entry exists that day' do
      get :show, params: { year: 2099, month: 1, day: 1 }

      expect(response).to redirect_to(entries_path)
      expect(flash[:alert]).to eq('Entry not found.')
    end
  end

  describe 'edit' do
    it 'should redirect to sign in if not logged in' do
      get :edit, params: { id: entry.id }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should edit entry' do
      sign_in user
      get :edit, params: { id: entry.id }
      expect(response.status).to eq 200
      expect(response.body).to have_content(entry.formatted_body)
    end
  end

  describe 'new' do
    it 'should redirect to sign in if not logged in' do
      get :new
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should let me create an entry' do
      sign_in user
      get :new
      expect(response.status).to eq 200
      expect(response.body).to have_content('NEW ENTRY')
    end
  end

  describe 'create' do
    let(:params) do
      { entry: {
        entry: 'Testing body',
        date: Time.now,
        image_url: 'https://dabble.me/favicon-32x32.png',
        inspiration_id: inspiration.id } }
    end

    it 'should redirect to sign in if not logged in' do
      expect { post :create, params: params }.not_to change { Entry.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should not let me create an entry if free user' do
      sign_in user
      expect { post :create, params: params }.not_to change { Entry.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(root_path)
    end

    it 'should let me create an entry if paid user' do
      sign_in user
      user.plan = 'PRO PayHere Monthly'
      user.save
      params[:entry][:date] = Date.new(2027, 3, 15)
      expect { post :create, params: params }.to change { Entry.count }.by(1)
      expect(response.status).to eq 302
      expect(response).to redirect_to(day_entry_url(year: 2027, month: 3, day: 15))
    end

    it 'should merge into an existing same-day entry if paid user' do
      sign_in paid_user
      existing = paid_user.entries.create!(date: Time.utc(2026, 8, 1, 15, 0, 0), body: '<p>Morning</p>')
      merge_params = {
        entry: {
          entry: 'Afternoon addition',
          date: Time.utc(2026, 8, 1, 9, 0, 0),
          inspiration_id: inspiration.id
        }
      }

      expect { post :create, params: merge_params }.not_to change { Entry.count }
      expect(response).to redirect_to(day_entry_url(year: 2026, month: 8, day: 1))
      expect(existing.reload.body).to include('Morning')
      expect(existing.body).to include('Afternoon addition')
    end
  end

  describe 'update with a blank body' do
    let(:blank_params) do
      { id: paid_entry.id, entry: { entry: '', date: paid_entry.date.strftime('%B %-d, %Y') } }
    end

    before do
      paid_entry
      sign_in paid_user
    end

    it 'deletes the entry and returns to the page the edit started from' do
      return_to = entries_calendar_url
      expect { put :update, params: blank_params, session: { return_to: return_to } }.to change { Entry.count }.by(-1)
      expect(response).to redirect_to(return_to)
      expect(flash[:notice]).to eq('Entry deleted!')
    end

    it 'falls back to entries when the stored location is another host' do
      put :update, params: blank_params, session: { return_to: 'https://evil.example/phish' }
      expect(response).to redirect_to(entries_path)
    end

    it 'falls back to entries when no location was stored' do
      put :update, params: blank_params
      expect(response).to redirect_to(entries_path)
    end
  end

  describe 'destroy' do
    it 'should redirect to sign in if not logged in' do
      delete :destroy, params: { id: entry.id }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it "deletes a free user's own entries (editing is PRO, deleting isn't)" do
      sign_in user
      expect(user).to be_is_free
      expect { delete :destroy, params: { id: entry.id } }.to change { Entry.count }.by(-1)
      expect(response).to redirect_to(entries_path)
    end

    it 'should delete pro user entries' do
      sign_in user
      user.plan = 'PRO PayHere Monthly'
      user.save
      expect { delete :destroy, params: { id: entry.id } }.to change { Entry.count }.by(-1)
    end

    it "should not delete entries that are not the user's" do
      sign_in user
      expect { delete :destroy, params: { id: not_my_entry.id } }.not_to change { Entry.count }
    end
  end

  describe 'calendar' do
    it 'should redirect to sign in if not logged in' do
      get :calendar
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should show me the page' do
      sign_in user
      get :calendar
      expect(response.status).to eq 200
      expect(response.body).to have_content('Calendar View')
    end

    it 'renders month and year jump controls for the current month' do
      sign_in user
      today = Time.now.in_time_zone(user.send_timezone).to_date
      get :calendar
      expect(response.body).to have_select('calendar-month', selected: today.strftime('%B'))
      expect(response.body).to have_select('calendar-year', selected: today.year.to_s)
      expect(response.body).to include("defaultDate: '#{today.strftime('%Y-%m-%d')}'")
    end

    it 'opens a requested month from the day param' do
      sign_in user
      entry.update_columns(date: Time.utc(2016, 3, 11))
      get :calendar, params: { day: '2016-03' }
      expect(response.status).to eq 200
      expect(response.body).to have_select('calendar-month', selected: 'March')
      expect(response.body).to have_select('calendar-year', selected: '2016')
      expect(response.body).to include("defaultDate: '2016-03-01'")
    end

    it 'opens a requested day from a full ISO date param' do
      sign_in user
      entry.update_columns(date: Time.utc(2016, 3, 11))
      get :calendar, params: { day: '2016-03-11' }
      expect(response.status).to eq 200
      expect(response.body).to have_select('calendar-month', selected: 'March')
      expect(response.body).to have_select('calendar-year', selected: '2016')
      expect(response.body).to include("defaultDate: '2016-03-11'")
    end

    it 'limits the year selector to the earliest entry year' do
      sign_in user
      entry.update_columns(date: Time.utc(2019, 6, 15))
      get :calendar
      expect(response.body).to have_css('#calendar-year option[value="2019"]')
      expect(response.body).not_to have_css('#calendar-year option[value="2018"]')
    end

    it 'ignores an invalid day param' do
      sign_in user
      today = Time.now.in_time_zone(user.send_timezone).to_date
      get :calendar, params: { day: 'not-a-date' }
      expect(response.status).to eq 200
      expect(response.body).to include("defaultDate: '#{today.strftime('%Y-%m-%d')}'")
    end
  end

  describe 'latest' do
    it 'should redirect to sign in if not logged in' do
      get :latest
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    def write(owner, body, date)
      FactoryBot.create(:entry, user: owner, body: body, date: date)
    end

    # A PRO account with no entries of its own yet.
    let(:pro) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere') }
    let(:today) { Time.now.in_time_zone(pro.send_timezone).to_date }

    it "shows today's entry labelled TODAY, without a greeting, search or the latest entry" do
      sign_in pro
      write(pro, 'Something from last week', today - 6)
      write(pro, 'What I wrote today', today)
      get :latest
      body = response.body

      expect(response.status).to eq 200
      expect(body).to have_content('TODAY')
      expect(body).to have_content('What I wrote today')
      expect(body).not_to have_content('Something from last week')
      expect(body).not_to include('Welcome back', 'LATEST ENTRY', 'Search your entries', 'Write today')
      expect(body).not_to have_content(entry.formatted_body)
    end

    it 'asks for an entry when today has none, and shows no older entry in its place' do
      sign_in pro
      write(pro, 'Something from last week', today - 6)
      get :latest
      body = response.body

      expect(body).to include('Write today')
      expect(Nokogiri::HTML(body).css('.label-past-years').map(&:text)).to eq([today.strftime('%A, %B %-d')])
      expect(body).not_to have_content('Something from last week')
    end

    it 'shows every entry written on this day in earlier years, however far back' do
      sign_in pro
      write(pro, 'One year back', today.prev_year(1))
      write(pro, 'Five years back', today.prev_year(5))
      write(pro, 'Nine years back', today.prev_year(9))
      write(pro, 'Same year, other day', today - 40)
      write(pro, 'Last year, a day off', today.prev_year(1) + 1)
      get :latest
      body = response.body

      expect(body.index('One year back')).to be < body.index('Five years back')
      expect(body.index('Five years back')).to be < body.index('Nine years back')
      expect(Nokogiri::HTML(body).css('.s-entry-header .label-past-years').map(&:text))
        .to eq(['ON THIS DAY 1 YEAR AGO', 'ON THIS DAY 5 YEARS AGO', 'ON THIS DAY 9 YEARS AGO'])
      expect(body).not_to have_content('Same year, other day')
      expect(body).not_to have_content('Last year, a day off')
    end

    it 'keeps entries from this day in earlier years for PRO accounts only' do
      sign_in user
      write(user, 'One year back', today.prev_year(1))
      get :latest

      expect(response.body).not_to have_content('One year back')
    end

    it 'shows Year in Progress under today, with day links that open in the same tab' do
      sign_in user
      get :latest
      body = response.body

      expect(body.index('Write today') || body.index('>TODAY<')).to be < body.index('Year in Progress')
      expect(body).not_to include('of the year completed', 'Write your memories down')

      day_links = Nokogiri::HTML(body).css('#year-in-review a.day')
      expect(day_links).not_to be_empty
      expect(day_links.map { |link| link['target'] }.compact).to be_empty
    end

    it 'should show a CTA to logged in users without entries' do
      sign_in user
      user.plan = 'PRO PayHere Monthly'
      user.save
      expect { delete :destroy, params: { id: entry.id } }.to change { Entry.count }.by(-1)
      get :latest
      expect(response.status).to eq 200
      expect(response.body).to have_content("reply to the email from Dabble Me to create your first entry")
    end
  end

  describe 'photos' do
    def photo_entry(owner, date)
      entry = FactoryBot.create(:entry, user: owner, body: 'A day with a photo', date: date)
      entry.update_columns(image: 'photo.jpg')
      entry
    end

    it 'shows a grid of photos, each linking to its entry, without entry text' do
      sign_in paid_user
      newer = photo_entry(paid_user, Date.new(2026, 3, 2))
      older = photo_entry(paid_user, Date.new(2026, 3, 1))
      FactoryBot.create(:entry, user: paid_user, body: 'No photo here', date: Date.new(2026, 3, 3))
      photo_entry(user, Date.new(2026, 3, 4))

      get :index, params: { group: 'photos' }
      links = Nokogiri::HTML(response.body).css('.s-photo-grid a.s-photo-grid__photo')

      expect(response.status).to eq 200
      expect(links.map { |link| link['href'] }).to eq([entry_path(newer), entry_path(older)])
      expect(links.map { |link| link['target'] }.compact).to be_empty
      expect(links.first.at_css('img')['src']).to include('/cdn-cgi/image/width=480,height=480,fit=cover,quality=80/https://')
      expect(response.body).not_to have_content('A day with a photo')
    end

    it 'sends someone with no photos back to the home page' do
      sign_in paid_user
      get :index, params: { group: 'photos' }

      expect(response).to redirect_to(latest_entry_path)
    end
  end

  describe 'songs' do
    def song_entry(body)
      entry = FactoryBot.create(:entry, user: paid_user, body: body, date: Date.new(2026, 3, 1))
      entry.update_columns(songs: [{ 'spotify_id' => 'abc123', 'artists' => ['Artist'], 'title' => 'Title' }])
      entry
    end

    it 'shows the start of a long entry with the rest behind Read more' do
      sign_in paid_user
      song_entry("<p>#{'Windows down the whole way. ' * 20}</p><p>The very last line.</p>")

      get :spotify
      page = Nokogiri::HTML(response.body)
      blurb = page.at_css('.s-blurb > .s-blurb__text').text

      expect(blurb.length).to be <= Entry::BLURB_LENGTH
      expect(blurb).to start_with('Windows down the whole way.').and end_with('...')
      expect(page.at_css('.s-blurb__more > summary').text).to eq('Read more')
      expect(page.at_css('.s-blurb__more').text).to include('The very last line.')
      expect(page.at_css('.s-blurb__more')['open']).to be_nil
    end

    it 'shows a short entry whole, with nothing to expand' do
      sign_in paid_user
      song_entry('<p>Short and sweet.</p>')

      get :spotify
      page = Nokogiri::HTML(response.body)

      expect(page.at_css('.s-blurb__text').text).to eq('Short and sweet.')
      expect(page.at_css('.s-blurb__more')).to be_nil
    end
  end

  describe 'export' do
    it 'should redirect to sign in if not logged in' do
      get :export, format: 'txt'
      expect(response.status).to eq 401
      expect(response.body).to eq 'You need to login or sign up before continuing.'
    end

    it 'queues an export and sends no entry text' do
      sign_in user
      expect(ExportEntriesJob).to receive(:perform_later).with(kind_of(Integer), {})
      expect { get :export }.to change { user.exports.count }.by(1)
      expect(response).to redirect_to(edit_user_registration_path(anchor: 'export'))
      expect(response.body).not_to include(entry.formatted_body)
    end
  end
end
