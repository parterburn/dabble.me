require 'rails_helper'

describe User do
  let(:user) { User.create(email: Faker::Internet.email, password: Faker::Internet.password(min_length: 8), first_name: Faker::Name.first_name, last_name: Faker::Name.last_name) }

  describe 'blocked email domains' do
    let(:password) { 'password1' }

    def build_user(email)
      User.new(email: email, password: password, password_confirmation: password)
    end

    it 'rejects a blocked domain on signup' do
      record = build_user('probe@pentest2bot.ink')

      expect(record).not_to be_valid
      expect(record.errors[:email]).to include('is not allowed')
    end

    it 'rejects a subdomain and ignores case' do
      record = build_user('Probe@mail.Pentest2Bot.ink')

      expect(record).not_to be_valid
      expect(record.errors[:email]).to include('is not allowed')
    end

    it 'allows an address that only shares a suffix' do
      record = build_user('person@notpentest2bot.ink')

      record.validate
      expect(record.errors[:email]).to be_empty
    end

    it 'rejects changing an existing account onto a blocked domain' do
      user.email = 'probe@pentest2bot.ink'

      expect(user).not_to be_valid
      expect(user.errors[:email]).to include('is not allowed')
    end
  end

  let(:doorkeeper_app) do
    Doorkeeper::Application.find_or_create_by!(uid: 'rspec-oauth-app') do |a|
      a.name = 'RSpec OAuth'
      a.redirect_uri = 'http://127.0.0.1/cb'
      a.scopes = 'mcp:access'
      a.confidential = false
    end
  end

  before :each do
    # Keep these recent (for pure-random examples) but avoid landing on the 5th or
    # Feb 29 — several examples use entry_date on Oct 5 / Feb 29, and with
    # way_back_past_entries defaulting to true those would match first.
    recent_dates = (2..20).map { |n| n.days.ago.to_date }
                           .reject { |d| d.day == 5 || (d.month == 2 && d.day == 29) }
                           .first(4)
    recent_dates.each { |date| user.entries.create(body: 'hi.', date: date) }
  end

  describe "#random_entry" do
    it "returns leap year entry" do
      entry_date = Date.parse("2020-2-29")
      past_entry = user.entries.create(date: Date.parse("2016-2-29"), body: "Hi from past leap year.")
      user.way_back_past_entries = true
      expect(user.random_entry(entry_date)).to eq(past_entry)
    end

    it "returns same day, way back" do
      entry_date = Date.parse("2019-10-5")
      past_entry = user.entries.create(date: Date.parse("2003-10-5"), body: "Hi from way back.")
      user.way_back_past_entries = true
      expect(user.random_entry(entry_date)).to eq(past_entry)
    end

    it "returns 1 year ago" do
      entry_date = Date.parse("2019-10-5")
      past_entry = user.entries.create(date: Date.parse("2018-10-5"), body: "Hi from 1 year back.")
      user.way_back_past_entries = false
      expect(user.random_entry(entry_date)).to eq(past_entry)
    end

    it "returns 1 month ago" do
      user.way_back_past_entries = false
      user.emails_sent = 3
      entry_date = Date.parse("2019-10-5")
      past_entry = user.entries.create(date: Date.parse("2019-9-5"), body: "Hi from 1 month back.")
      expect(user.random_entry(entry_date)).to eq(past_entry)
    end

    it "returns 1 week ago" do
      user.way_back_past_entries = false
      user.emails_sent = 5
      entry_date = Date.parse("2019-10-5")
      past_entry = user.entries.create(date: Date.parse("2019-9-28"), body: "Hi from 1 week back.")
      expect(user.random_entry(entry_date)).to eq(past_entry)
    end

    it "returns random from way back" do
      user.emails_sent = 2
      user.way_back_past_entries = true
      entry_date = Date.parse("2019-10-5")
      (1..31).each do |i|
        user.entries.create(date: Date.parse("2015-1-#{i}"), body: "Hi from way back.")
      end
      expect(user.random_entry(entry_date).date.year).to eq(2015)
    end

    it "returns pure random, including way back" do
      user.way_back_past_entries = true
      entry_date = Date.parse("2019-10-5")
      user.entries.create(date: Date.parse("2016-1-15"), body: "hi.")
      expect(user.random_entry(entry_date).body).to eq("hi.")
    end

    it "returns pure random, not way back" do
      user.way_back_past_entries = false
      entry_date = Date.parse("2019-10-5")
      user.entries.create(date: Date.parse("2016-1-15"), body: "Hi from way back.")
      user.entries.create(date: Date.parse("2018-10-3"), body: "Hi from a few days ago.")
      expect(user.random_entry(entry_date).date.year).not_to eq(2015)
    end

  end

  describe 'Doorkeeper OAuth when downgrading from PRO' do
    it 'revokes access tokens and grants when plan changes from PRO to Free' do
      u = FactoryBot.create(:user, plan: 'PRO Monthly PayHere', payhere_id: '999', gumroad_id: '999999999999')
      token = Doorkeeper::AccessToken.create!(
        resource_owner_id: u.id,
        application_id: doorkeeper_app.id,
        scopes: 'mcp:access',
        expires_in: 7200
      )
      grant = Doorkeeper::AccessGrant.create!(
        resource_owner_id: u.id,
        application_id: doorkeeper_app.id,
        token: SecureRandom.hex(32),
        expires_in: 600,
        redirect_uri: 'http://127.0.0.1/cb',
        scopes: 'mcp:access',
        created_at: Time.current
      )
      expect(token.reload.revoked_at).to be_nil
      expect(grant.reload.revoked_at).to be_nil

      u.update!(plan: 'Free')

      expect(token.reload.revoked_at).to be_present
      expect(grant.reload.revoked_at).to be_present
    end

    it 'does not revoke when changing between PRO plans' do
      u = FactoryBot.create(:user, plan: 'PRO Monthly PayHere', payhere_id: '999', gumroad_id: '999999999999')
      token = Doorkeeper::AccessToken.create!(
        resource_owner_id: u.id,
        application_id: doorkeeper_app.id,
        scopes: 'mcp:access',
        expires_in: 7200
      )
      u.update!(plan: 'PRO Yearly PayHere', payhere_id: '999')

      expect(token.reload.revoked_at).to be_nil
    end

    it 'revokes access tokens and grants when password, email, or OTP secret changes' do
      u = FactoryBot.create(:user, plan: 'PRO Monthly PayHere', payhere_id: '999', gumroad_id: '999999999999')
      u.generate_otp_secret
      u.update!(otp_enabled: true, otp_enabled_on: Time.current)

      token = Doorkeeper::AccessToken.create!(
        resource_owner_id: u.id,
        application_id: doorkeeper_app.id,
        scopes: 'mcp:access',
        expires_in: 7200,
        use_refresh_token: true
      )
      grant = Doorkeeper::AccessGrant.create!(
        resource_owner_id: u.id,
        application_id: doorkeeper_app.id,
        token: SecureRandom.hex(32),
        expires_in: 600,
        redirect_uri: 'http://127.0.0.1/cb',
        scopes: 'mcp:access',
        created_at: Time.current
      )

      u.update!(password: 'NewSecurePass123!', password_confirmation: 'NewSecurePass123!')
      expect(token.reload.revoked_at).to be_present
      expect(grant.reload.revoked_at).to be_present

      token2 = Doorkeeper::AccessToken.create!(
        resource_owner_id: u.id,
        application_id: doorkeeper_app.id,
        scopes: 'mcp:access',
        expires_in: 7200
      )
      u.update!(email: "updated-#{Faker::Internet.email}")
      expect(token2.reload.revoked_at).to be_present

      token3 = Doorkeeper::AccessToken.create!(
        resource_owner_id: u.id,
        application_id: doorkeeper_app.id,
        scopes: 'mcp:access',
        expires_in: 7200
      )
      u.disable_otp!
      expect(token3.reload.revoked_at).to be_present
    end
  end

  describe 'OTP challenge and recovery token protections' do
    around do |example|
      original_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original_cache
    end

    it 'does not advance otp_recovery_counter on failed recovery guesses' do
      user.generate_otp_secret
      user.update!(otp_enabled: true, otp_enabled_on: Time.current)
      initial_counter = user.otp_recovery_counter
      first_recovery_code = user.next_otp_recovery_tokens(1)[initial_counter]

      3.times do
        expect(user.validate_otp_recovery_token('000000')).to be_falsey
      end

      expect(user.reload.otp_recovery_counter).to eq(initial_counter)
      expect(user.validate_otp_recovery_token(first_recovery_code)).to be_truthy
      expect(user.reload.otp_recovery_counter).to eq(initial_counter + 1)
    end

    it 'clears otp_session_challenge after OTP_MAX_CHALLENGE_FAILURES wrong attempts' do
      user.generate_otp_secret
      user.update!(otp_enabled: true, otp_enabled_on: Time.current)
      challenge = user.generate_otp_challenge!
      expect(challenge).to be_present

      (User::OTP_MAX_CHALLENGE_FAILURES - 1).times do
        expect(user.validate_otp_token('000000')).to be_falsey
        expect(user.reload.otp_session_challenge).to eq(challenge)
      end

      expect(user.validate_otp_token('000000')).to be_falsey
      expect(user.reload.otp_session_challenge).to be_nil
      expect(user.otp_challenge_expires).to be_nil
    end

    it 'clears otp_session_challenge immediately when a valid OTP code is verified' do
      user.generate_otp_secret
      user.update!(otp_enabled: true, otp_enabled_on: Time.current)
      challenge = user.generate_otp_challenge!
      expect(challenge).to be_present

      valid_code = ROTP::TOTP.new(user.otp_auth_secret).now
      expect(user.validate_otp_token(valid_code)).to be_truthy
      expect(user.reload.otp_session_challenge).to be_nil
      expect(user.otp_challenge_expires).to be_nil
    end
  end

  describe '#cancel_pending_deletion!' do
    it 'clears deleted_at when deletion is pending' do
      user.update_column(:deleted_at, Time.current)
      expect(user.cancel_pending_deletion!).to eq(true)
      expect(user.reload.deleted_at).to be_nil
    end

    it 'returns false when deletion is not pending' do
      expect(user.cancel_pending_deletion!).to eq(false)
    end
  end

  describe '#send_devise_notification' do
    around do |example|
      ActiveJob::Base.queue_adapter = :test
      example.run
    ensure
      ActiveJob::Base.queue_adapter = :inline
    end

    it 'enqueues reset password instructions instead of delivering them synchronously' do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect do
        user.send_reset_password_instructions
      end.to have_enqueued_mail(Devise::Mailer, :reset_password_instructions)
    end
  end

  describe '#existing_entry' do
    it 'finds an entry stored at a non-midnight datetime on that calendar day' do
      entry = user.entries.create!(date: Time.utc(2099, 3, 15, 18, 45, 0), body: 'afternoon')

      expect(user.existing_entry('2099-03-15')).to eq(entry)
      expect(user.existing_entry(Date.new(2099, 3, 15))).to eq(entry)
      expect(user.existing_entry('2099-03-16')).to be_nil
    end
  end
end
