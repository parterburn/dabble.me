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
      sign_in superuser
      get :users
      expect(response.status).to eq 200
      expect(response.body).to have_content('Admin Users')
    end

    it "links each user to their edit page, and a paid user's amount to their payments" do
      Payment.create!(user: paid_user, amount: 3.0, comments: 'Monthly', date: Time.now)
      sign_in superuser
      get :users
      expect(response.body).to have_link(href: edit_admin_user_path(user))
      expect(response.body).to have_link('$3.00', href: payments_path(user_id: paid_user.id))
    end
  end

  describe 'edit_user' do
    it 'redirects a non-admin' do
      sign_in user
      get :edit_user, params: { id: paid_user.id }
      expect(response).to redirect_to(entries_path)
    end

    it "shows the user's settings, plan and a password reset button" do
      sign_in superuser
      get :edit_user, params: { id: paid_user.id }
      expect(response.status).to eq 200
      expect(response.body).to have_field('user_email', with: paid_user.email)
      expect(response.body).to have_select('user_plan', selected: 'PRO Monthly PayHere (Stripe)')
      expect(response.body).to have_checked_field('frequency_Sun')
      expect(response.body).to have_button('Send password reset')
    end
  end

  describe 'update_user' do
    let(:params) do
      {
        id: paid_user.id,
        user: { first_name: 'Ada', last_name: 'Lovelace', email: 'ada@example.com', send_time: '07:00',
                send_timezone: 'Pacific Time (US & Canada)', plan: 'PRO Yearly PayHere' },
        frequency: ['', 'Mon', 'Wed']
      }
    end

    before { sign_in superuser }

    it 'saves the basic settings and plan' do
      patch :update_user, params: params

      expect(response).to redirect_to(edit_admin_user_path(paid_user))
      paid_user.reload
      expect(paid_user.full_name).to eq 'Ada Lovelace'
      expect(paid_user.email).to eq 'ada@example.com'
      expect(paid_user.frequency).to eq %w[Mon Wed]
      expect(paid_user.send_time.strftime('%H:%M')).to eq '07:00'
      expect(paid_user.send_timezone).to eq 'Pacific Time (US & Canada)'
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

  describe 'send_password_reset' do
    include ActiveJob::TestHelper

    it 'emails the user a reset link' do
      sign_in superuser
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
      sign_in superuser
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
      sign_in superuser
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
      sign_in superuser
      expect { post :capture_stats }.to change(BusinessMetricSnapshot, :count).by(1)
      expect(BusinessMetricSnapshot.last.captured_on).to eq(Date.current)
      expect(response).to redirect_to(admin_stats_path)
    end
  end
end
