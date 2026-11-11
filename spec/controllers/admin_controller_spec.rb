require 'rails_helper'

RSpec.describe AdminController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    superuser
  end

  describe 'users' do
    it 'should redirect to root url if not logged in' do
      get :users
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries if not superuser' do
      sign_in user
      get :users
      expect(response.status).to eq 302
      expect(response).to redirect_to(entries_path)
    end

    it 'should show Admin Users to superusers' do
      sign_in_admin superuser
      get :users
      expect(response.status).to eq 200
      expect(response.body).to have_content('Admin Users')
    end

    it "links each user to their edit page, and a paid user's amount to their payments" do
      Payment.create!(user: paid_user, amount: 3.0, comments: 'Monthly', date: Time.now)
      sign_in_admin superuser
      get :users
      expect(response.body).to have_link(href: edit_admin_user_path(user))
      expect(response.body).to have_link('$3.00', href: payments_path(user_id: paid_user.id))
    end

    context 'filtering' do
      let!(:zora) { FactoryBot.create(:user, first_name: 'Zorabel', last_name: 'Quenneville', email: 'zora@example.com') }

      before { sign_in_admin superuser }

      it 'finds users by first or last name' do
        get :users, params: { name: 'quenneville ZORA' }
        expect(response.body).to have_field('name', with: 'quenneville ZORA')
        expect(response.body).to have_link(href: edit_admin_user_path(zora))
        expect(response.body).not_to have_link(href: edit_admin_user_path(user))
      end

      it 'applies every filter that is filled in' do
        get :users, params: { name: 'zorabel', email: 'zora@' }
        expect(response.body).to have_link(href: edit_admin_user_path(zora))

        get :users, params: { name: 'zorabel', email: user.email }
        expect(response.body).to have_content('No users match.')

        get :users, params: { name: 'zorabel', user_key: user.user_key }
        expect(response.body).to have_content('No users match.')
      end
    end
  end

  describe 'photos' do
    before { sign_in_admin superuser }

    def photo_entries(count, date: Date.new(2026, 1, 1))
      Entry.insert_all(Array.new(count) { |i| { user_id: paid_user.id, date: date, image: "photo#{i}.jpg" } })
    end

    it 'shows up to 300 photos a page, past the usual 100-per-page cap' do
      photo_entries(301)

      get :photos
      expect(response.body).to have_css('img[src*="photo"]', count: 300)
      expect(response.body).to have_link(href: admin_photos_path(page: 2))
    end

    it 'shows the newest first, a page at a time' do
      stub_const('AdminController::PHOTOS_PER_PAGE', 1)
      photo_entries(1, date: Date.new(2026, 1, 1))
      photo_entries(1, date: Date.new(2026, 2, 1))

      get :photos
      expect(response.body).to have_css('img[alt="February 1, 2026"]')
      expect(response.body).not_to have_css('img[alt="January 1, 2026"]')

      get :photos, params: { page: 2 }
      expect(response.body).to have_css('img[alt="January 1, 2026"]')
    end
  end

  describe 'AI cost' do
    before do
      sign_in_admin superuser
      AiUsage.create!(user: paid_user, model: 'claude-opus-5-5', input_tokens: 3000, output_tokens: 400, cost_usd: 1.2)
      AiUsage.create!(user: paid_user, model: 'claude-sonnet-5-5', input_tokens: 3000, output_tokens: 400, cost_usd: 0.05)
      AiUsage.create!(user: user, model: 'claude-opus-5-5', input_tokens: 10, output_tokens: 5, cost_usd: 0.0002)
    end

    it "shows each user's total in the users list" do
      get :users
      page = Capybara.string(response.body)

      expect(page).to have_css('th', text: 'AI cost')
      expect(page.find('tr', text: paid_user.email)).to have_css('td[data-value="1.25"]', text: '$1.25')
      expect(page.find('tr', text: user.email)).to have_css('td', text: '<$0.01')
      expect(page.find('tr', text: superuser.email)).to have_css('td[data-value="0.0"]', text: '—')
    end

    it 'shows the count and total on the edit page' do
      get :edit_user, params: { id: paid_user.id }
      expect(Capybara.string(response.body)).to have_css('div', text: /AI reflections\s*2 · \$1\.25/)
    end
  end

  describe 'edit_user' do
    it 'redirects a non-admin' do
      sign_in user
      get :edit_user, params: { id: paid_user.id }
      expect(response).to redirect_to(entries_path)
    end

    it "shows the user's settings, plan and a password reset button" do
      sign_in_admin superuser
      get :edit_user, params: { id: paid_user.id }
      expect(response.status).to eq 200
      expect(response.body).to have_field('user_email', with: paid_user.email)
      expect(response.body).to have_select('user_plan', selected: 'PRO Monthly PayHere (Stripe)')
      expect(response.body).to have_checked_field('frequency_Sun')
      expect(response.body).to have_checked_field('user_send_updates')
      expect(response.body).to have_button('Send password reset')
    end
  end

  describe 'update_user' do
    let(:params) do
      {
        id: paid_user.id,
        user: { first_name: 'Ada', last_name: 'Lovelace', email: 'ada@example.com', send_time: '07:00',
                send_timezone: 'Pacific Time (US & Canada)', send_updates: '0', plan: 'PRO Yearly PayHere' },
        frequency: ['', 'Mon', 'Wed']
      }
    end

    before { sign_in_admin superuser }

    it 'saves the basic settings and plan' do
      patch :update_user, params: params

      expect(response).to redirect_to(edit_admin_user_path(paid_user))
      paid_user.reload
      expect(paid_user.full_name).to eq 'Ada Lovelace'
      expect(paid_user.email).to eq 'ada@example.com'
      expect(paid_user.frequency).to eq %w[Mon Wed]
      expect(paid_user.send_time.strftime('%H:%M')).to eq '07:00'
      expect(paid_user.send_timezone).to eq 'Pacific Time (US & Canada)'
      expect(paid_user.send_updates).to be(false)
      expect(paid_user.plan).to eq 'PRO Yearly PayHere'
      expect(flash[:notice]).to eq 'Saved ada@example.com.'
    end

    it 'turns the emails off when every day is unticked' do
      patch :update_user, params: params.merge(frequency: [''])
      expect(paid_user.reload.frequency).to eq []
    end

    it "says so when a Free user's extra days are dropped" do
      patch :update_user, params: params.merge(id: user.id, user: { plan: 'Free' })
      expect(user.reload.frequency).to eq ['Sun']
      expect(flash[:notice]).to include('Free accounts get Sunday emails only')
    end

    it 'shows the error and changes nothing when the email is taken' do
      patch :update_user, params: params.deep_merge(user: { email: user.email })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to have_content('Email has already been taken')
      expect(paid_user.reload.first_name).not_to eq 'Ada'
    end

    it 'does nothing for a non-admin' do
      sign_in user
      patch :update_user, params: params
      expect(response).to redirect_to(entries_path)
      expect(paid_user.reload.email).not_to eq 'ada@example.com'
    end
  end

  describe 'ignored email images' do
    let(:image_url) { "https://d10r8m94hrfowu.cloudfront.net/#{paid_user.image_key}/2026-09-20/sig.jpg" }

    def add(kind, value, id: paid_user.id)
      post :create_ignored_email_image, params: { id: id, ignored_email_image: { kind: kind, value: value } }
    end

    before { sign_in_admin superuser }

    it "lists the user's rules on their page, with a form to add one" do
      IgnoredEmailImage.create!(user: paid_user, kind: "filename", pattern: "b_logo.png")
      IgnoredEmailImage.create!(user: user, kind: "filename", pattern: "not-theirs.png")

      get :edit_user, params: { id: paid_user.id }

      expect(response.body).to have_content('Ignored email images')
      expect(response.body).to have_css('code', text: 'b_logo.png')
      expect(response.body).not_to have_content('not-theirs.png')
      expect(response.body).to have_select('ignored_email_image_kind', selected: 'Looks like this image')
      expect(response.body).to have_button('Add')
    end

    it 'adds an image rule from a link to the saved image' do
      allow(CollageGenerator).to receive(:fetch).with(image_url).and_return(stored_copy(jpeg_bytes(signature_logo)))

      expect { add("image", image_url) }.to change(paid_user.ignored_email_images, :count).by(1)

      rule = paid_user.ignored_email_images.last
      expect(rule.image_url).to eq(image_url)
      expect(rule.image_fingerprint).to be_detailed
      expect(response).to redirect_to(edit_admin_user_path(paid_user, anchor: 'ignored-email-images'))
    end

    it 'adds a filename rule' do
      add("filename", "Image001.jpg")
      expect(paid_user.ignored_email_images.pluck(:kind, :pattern)).to eq([%w[filename image001.jpg]])
    end

    it "shows why a rule couldn't be added and keeps what was typed" do
      allow(CollageGenerator).to receive(:fetch).and_return(nil)

      expect { add("image", image_url) }.not_to change(IgnoredEmailImage, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to have_content("That link couldn't be loaded as an image.")
      expect(response.body).to have_field('ignored_email_image_value', with: image_url)
    end

    it 'removes a rule' do
      rule = IgnoredEmailImage.create!(user: paid_user, kind: "filename", pattern: "b_logo.png")

      delete :destroy_ignored_email_image, params: { id: paid_user.id, ignored_email_image_id: rule.id }

      expect(IgnoredEmailImage.exists?(rule.id)).to be(false)
      expect(response).to redirect_to(edit_admin_user_path(paid_user, anchor: 'ignored-email-images'))
    end

    it "won't remove another user's rule through this user's page" do
      rule = IgnoredEmailImage.create!(user: user, kind: "filename", pattern: "b_logo.png")

      expect {
        delete :destroy_ignored_email_image, params: { id: paid_user.id, ignored_email_image_id: rule.id }
      }.to raise_error(ActiveRecord::RecordNotFound)
      expect(IgnoredEmailImage.exists?(rule.id)).to be(true)
    end

    it 'does nothing for a non-admin' do
      sign_in user
      add("filename", "b_logo.png")
      expect(response).to redirect_to(entries_path)
      expect(IgnoredEmailImage.count).to eq(0)
    end
  end

  describe 'send_password_reset' do
    include ActiveJob::TestHelper

    it 'emails the user a reset link' do
      sign_in_admin superuser
      expect { post :send_password_reset, params: { id: paid_user.id } }
        .to have_enqueued_mail(Devise::Mailer, :reset_password_instructions)
      expect(paid_user.reload.reset_password_token).to be_present
      expect(response).to redirect_to(edit_admin_user_path(paid_user))
      expect(flash[:notice]).to eq "Password reset email sent to #{paid_user.email}."
    end

    it 'sends nothing for a non-admin' do
      sign_in user
      expect { post :send_password_reset, params: { id: paid_user.id } }
        .not_to have_enqueued_mail(Devise::Mailer, :reset_password_instructions)
      expect(response).to redirect_to(entries_path)
    end
  end

  describe 'stats' do
    it 'should redirect to root url if not logged in' do
      get :stats
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries if not superuser' do
      sign_in user
      get :stats
      expect(response.status).to eq 302
      expect(response).to redirect_to(entries_path)
    end

    it 'should show Admin Stats to superusers' do
      sign_in_admin superuser
      get :stats
      expect(response.status).to eq 200
      expect(response.body).to have_content('Admin Stats')
      expect(response.body).to have_content('ARR')
      expect(response.body).to have_content('MRR')
      expect(response.body).to have_content('Pricing cohorts')
      expect(response.body).to have_content('PRO / Free')
      expect(response.body).to have_content('MCP')
      expect(response.body).to have_content('Connected now')
    end

    it 'does not call Mailgun while rendering the page' do
      expect(BusinessMetrics::MailgunStats).not_to receive(:fetch)
      sign_in_admin superuser
      get :stats
      expect(response.status).to eq 200
    end
  end

  describe 'capture_stats' do
    before do
      allow(BusinessMetrics::MailgunStats).to receive(:fetch).and_return(
        BusinessMetrics::MailgunStats::Result.new(sent: 0, failed: 0, opened: 0, complained: 0)
      )
    end

    it 'redirects non-admins' do
      sign_in user
      post :capture_stats
      expect(response).to redirect_to(entries_path)
    end

    it 'snapshots metrics for superusers' do
      sign_in_admin superuser
      expect { post :capture_stats }.to change(BusinessMetricSnapshot, :count).by(1)
      expect(BusinessMetricSnapshot.last.captured_on).to eq(Date.current)
      expect(response).to redirect_to(admin_stats_path)
    end
  end
end
