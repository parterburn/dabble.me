require 'rails_helper'

RSpec.describe 'Encrypted columns' do
  let(:user) { FactoryBot.create(:user, first_name: 'Ann', last_name: 'Lee', past_filter: 'breakup') }

  it 'stores entry text as ciphertext and reads it back' do
    entry = FactoryBot.create(:entry, user: user, body: '<p>private thoughts</p>', original_email_body: 'raw reply')
    entry.update!(original_email: { 'headers' => { 'Subject' => 'Re: Sunday' } })

    %w[body original_email_body original_email].each do |column|
      expect(ciphertext?(stored_value(entry, column))).to be(true), "#{column} is not ciphertext"
      expect(stored_value(entry, column)).not_to include('private', 'raw reply', 'Sunday')
    end

    entry = Entry.find(entry.id)
    expect(entry.body).to eq('<p>private thoughts</p>')
    expect(entry.original_email_body).to eq('raw reply')
    expect(entry.original_email.dig('headers', 'Subject')).to eq('Re: Sunday')
  end

  it 'leaves a missing value as NULL' do
    entry = FactoryBot.create(:entry, user: user, body: 'text', original_email_body: nil)
    expect(stored_value(entry, 'original_email_body')).to be_nil
    expect(user.entries.only_email).to be_empty
  end

  it 'stores account secrets as ciphertext' do
    user.update!(otp_auth_secret: 'OTPSECRET', otp_recovery_secret: 'RECOVERY')
    %w[user_key image_key first_name last_name past_filter otp_auth_secret otp_recovery_secret].each do |column|
      expect(ciphertext?(stored_value(user, column))).to be(true), "#{column} is not ciphertext"
    end

    reloaded = User.find(user.id)
    expect(reloaded.first_name).to eq('Ann')
    expect(reloaded.past_filter).to eq('breakup')
    expect(reloaded.otp_auth_secret).to eq('OTPSECRET')
    expect(reloaded.user_key).to eq(user.user_key)
  end

  it 'finds users by posting key and photo key' do
    expect(User.find_by(user_key: user.user_key)).to eq(user)
    expect(User.find_by(image_key: user.image_key)).to eq(user)
    expect(User.find_by(user_key: user.user_key[0, 8])).to be_nil
  end

  it 'keeps posting keys unique' do
    other = FactoryBot.build(:user, user_key: user.user_key)
    expect(other).not_to be_valid
    expect(other.errors[:user_key]).to be_present
  end

  describe 'rows written before encryption' do
    it 'reads plaintext entry text and finds it in search' do
      entry = FactoryBot.create(:entry, user: user, body: 'placeholder')
      store_plaintext(entry, 'body', '<p>an older hiking entry</p>')

      expect(Entry.find(entry.id).body).to eq('<p>an older hiking entry</p>')
      expect(Search.new(user: user, term: 'hiking').entries.to_a).to eq([entry])
    end

    it 'finds a user by a plaintext posting key and keeps it unique' do
      store_plaintext(user, 'user_key', 'ulegacykey000000001')
      store_plaintext(user, 'image_key', 'ulegacykey000000001')

      expect(User.find_by(user_key: 'ulegacykey000000001')).to eq(user)
      expect(User.find_by(image_key: 'ulegacykey000000001')).to eq(user)
      expect(FactoryBot.build(:user, user_key: 'ulegacykey000000001')).not_to be_valid
    end

    it 'encrypts a plaintext row the next time it is saved' do
      entry = FactoryBot.create(:entry, user: user, body: 'placeholder')
      store_plaintext(entry, 'body', 'older text')

      Entry.find(entry.id).update!(body: 'older text, edited')
      expect(ciphertext?(stored_value(entry, 'body'))).to be(true)
    end

    it 'raises on plaintext once plaintext is no longer allowed' do
      entry = FactoryBot.create(:entry, user: user, body: 'placeholder')
      store_plaintext(entry, 'body', 'older text')
      config = ActiveRecord::Encryption.config
      config.support_unencrypted_data = false

      expect { Entry.find(entry.id).body }.to raise_error(ActiveRecord::Encryption::Errors::Decryption)
    ensure
      config.support_unencrypted_data = true
    end
  end

  describe Hashtag do
    it 'stores the tag as ciphertext and keeps it unique per user, ignoring case' do
      hashtag = user.original_hashtags.create!(tag: 'Birthday', date: Date.new(2020, 5, 1))
      expect(ciphertext?(stored_value(hashtag, 'tag'))).to be(true)
      expect(Hashtag.find(hashtag.id).tag).to eq('Birthday')

      expect(user.original_hashtags.build(tag: 'birthday', date: Date.new(2021, 5, 1))).not_to be_valid
      expect(FactoryBot.create(:user).original_hashtags.build(tag: 'birthday', date: Date.new(2021, 5, 1))).to be_valid
      expect(hashtag).to be_valid
    end
  end
end
