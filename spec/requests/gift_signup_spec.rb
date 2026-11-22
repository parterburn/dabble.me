require 'rails_helper'

# dabble.me/gift/<code>: a free year of PRO for a code listed in GIFT_CODES (Gift).
RSpec.describe 'Gift links', type: :request do
  let(:password) { 'a long password' }

  around do |example|
    previous = ENV['GIFT_CODES']
    ENV['GIFT_CODES'] = 'Family2026, friends:2'
    example.run
  ensure
    ENV['GIFT_CODES'] = previous
  end

  def sign_up(email, gift_code: nil)
    params = { user: { email: email, password: password, password_confirmation: password } }
    params[:gift_code] = gift_code if gift_code
    post user_registration_path, params: params
  end

  describe 'the gift page' do
    it 'shows the gift sign-up form for a listed code, in any case' do
      get gift_path('FAMILY2026')

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("You've been given a year of Dabble Me PRO")
      expect(response.body).to include('$40 value')
      expect(response.body).to include('name="gift_code"')
      expect(response.body).to include('Claim my year of PRO')
    end

    it 'sends an unknown code to the regular sign-up, saying the code is no longer valid' do
      get gift_path('nope')

      expect(response).to redirect_to(new_user_registration_path)
      expect(flash[:alert]).to eq('That gift code is no longer valid.')
    end

    it 'treats every code as invalid when GIFT_CODES is unset' do
      ENV['GIFT_CODES'] = nil
      get gift_path('family2026')

      expect(response).to redirect_to(new_user_registration_path)
    end

    it 'leaves the regular sign-up page as it was' do
      get new_user_registration_path

      expect(response.body).to include('Create your free account')
      expect(response.body).not_to include('gift_code')
    end
  end

  describe 'signing up from it' do
    it 'grants a year of PRO' do
      sign_up('gifted@example.com', gift_code: 'family2026')

      user = User.find_by(email: 'gifted@example.com')
      expect(user.plan).to eq(Gift::PLAN)
      expect(user).to be_is_pro
      expect(user.gift_expires_at).to be_within(1.minute).of(1.year.from_now)
      expect(user.gift_redemption.code).to eq('family2026')
      expect(user.payments).to be_empty
      expect(flash[:notice]).to include('Your gift of PRO runs until')
    end

    it 'still creates a Free account when the code stopped working before the form was sent' do
      sign_up('late@example.com', gift_code: 'retired')

      user = User.find_by(email: 'late@example.com')
      expect(user).to be_is_free
      expect(user.gift_redemption).to be_nil
      expect(flash[:alert]).to include('no longer valid')
    end

    it 'stops a capped code once it has been used up' do
      %w[one two].each do |name|
        sign_up("#{name}@example.com", gift_code: 'friends')
        sign_out :user
      end

      get gift_path('friends')
      expect(response).to redirect_to(new_user_registration_path)

      sign_up('three@example.com', gift_code: 'friends')
      expect(User.find_by(email: 'two@example.com')).to be_gifted_pro
      expect(User.find_by(email: 'three@example.com')).to be_is_free
    end

    it 'keeps the gift page when the form has an error' do
      post user_registration_path, params: {
        gift_code: 'family2026',
        user: { email: 'mismatch@example.com', password: password, password_confirmation: 'something else' }
      }

      expect(User.find_by(email: 'mismatch@example.com')).to be_nil
      expect(response.body).to include("You've been given a year of Dabble Me PRO")
    end
  end

  describe 'when signed in' do
    it 'lets a Free account add the gift' do
      user = FactoryBot.create(:user)
      sign_in user

      get gift_path('family2026')
      expect(response.body).to include('Add my year of PRO')

      post redeem_gift_path('family2026')
      expect(response).to redirect_to(edit_user_registration_path)
      expect(user.reload).to be_gifted_pro
    end

    it "doesn't touch an account that already pays for PRO" do
      user = FactoryBot.create(:user, plan: 'PRO Yearly PayHere')
      sign_in user

      post redeem_gift_path('family2026')

      expect(response).to redirect_to(root_path)
      expect(user.reload.plan).to eq('PRO Yearly PayHere')
      expect(user.gift_redemption).to be_nil
    end

    it 'allows one gift per account, even after the year is up' do
      user = FactoryBot.create(:user)
      GiftRedemption.create!(user: user, code: 'family2026', expires_at: 1.day.ago)
      sign_in user

      post redeem_gift_path('family2026')

      expect(flash[:alert]).to eq('This account has already used a gift of PRO.')
      expect(user.reload).to be_is_free
    end
  end

  describe 'when the year is up' do
    it 'moves the account back to Free, leaving gifts still running and paid plans alone' do
      lapsed = FactoryBot.create(:user, plan: Gift::PLAN)
      GiftRedemption.create!(user: lapsed, code: 'family2026', expires_at: 1.hour.ago)
      running = FactoryBot.create(:user, plan: Gift::PLAN)
      GiftRedemption.create!(user: running, code: 'family2026', expires_at: 1.month.from_now)
      # Subscribed after a gift: the paid plan is in charge now.
      subscribed = FactoryBot.create(:user, plan: 'PRO Yearly PayHere')
      GiftRedemption.create!(user: subscribed, code: 'family2026', expires_at: 1.hour.ago)
      FactoryBot.create(:payment, user: subscribed, amount: 40, date: 1.week.ago)

      UserDowngradeExpiredWorker.new.perform

      expect(lapsed.reload.plan).to eq('Free')
      expect(running.reload.plan).to eq(Gift::PLAN)
      expect(subscribed.reload.plan).to eq('PRO Yearly PayHere')
    end

    it 'keeps gifted accounts out of revenue' do
      FactoryBot.create(:user, plan: Gift::PLAN)

      expect(RevenueMetrics.current.subscribers).to be_empty
    end
  end
end
