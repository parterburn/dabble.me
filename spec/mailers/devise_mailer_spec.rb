require 'rails_helper'

RSpec.describe DeviseMailer do
  let(:user) { create(:user, email: 'ada@example.com', first_name: 'Ada') }
  let(:support_from) { "Dabble Me Support <hello@#{ENV['MAIN_DOMAIN']}>" }

  # :lockable and :confirmable are not enabled, so those routes are not
  # mounted. The templates still call the real helpers; define them only when
  # the app has not, so the messages can be rendered.
  def ensure_devise_url_helper(name, token_key)
    helpers = Devise::Controllers::UrlHelpers
    return if helpers.method_defined?(name)

    helpers.define_method(name) do |_resource = nil, **opts|
      "http://localhost/#{name}?#{token_key}=#{opts[token_key]}"
    end
  end

  before do
    ensure_devise_url_helper(:unlock_url, :unlock_token)
    ensure_devise_url_helper(:confirmation_url, :confirmation_token)
  end

  it 'is the mailer Devise sends' do
    expect(Devise.mailer).to eq(described_class)
  end

  describe '#reset_password_instructions' do
    let(:email) { described_class.reset_password_instructions(user, 'reset-token') }

    it 'comes from Dabble Me Support and greets the user by first name' do
      html = email.html_part.body.decoded
      text = email.text_part.body.decoded

      expect(email[:from].value).to eq(support_from)
      expect(email[:reply_to].value).to eq(support_from)
      expect(email.to).to eq(['ada@example.com'])
      expect(html).to include('Hey Ada,', "If this wasn't you", 'Change my password', 'Thanks,', 'Dabble Me', 'ada@example.com')
      expect(text).to include("Hey Ada,\n", "If this wasn't you", "Thanks,\nDabble Me", 'ada@example.com')
      expect(html).to include('reset_password_token=reset-token')
      expect(text).to include('reset_password_token=reset-token')
    end

    it 'uses the first-name fallback when the name is blank' do
      user.update!(first_name: '')

      text = described_class.reset_password_instructions(user, 'reset-token').text_part.body.decoded

      expect(text).to include('Hey there,')
    end
  end

  describe '#unlock_instructions' do
    it 'comes from Dabble Me Support and includes the unlock link' do
      email = described_class.unlock_instructions(user, 'unlock-token')
      html = email.html_part.body.decoded
      text = email.text_part.body.decoded

      expect(email[:from].value).to eq(support_from)
      expect(email[:reply_to].value).to eq(support_from)
      expect(html).to include('Hey Ada,', "If this wasn't you", 'Unlock my account', 'Thanks,', 'Dabble Me')
      expect(text).to include("Hey Ada,\n", "If this wasn't you", "Thanks,\nDabble Me")
      expect(html).to include('unlock_token=unlock-token')
      expect(text).to include('unlock_token=unlock-token')
    end
  end

  describe '#confirmation_instructions' do
    it 'keeps the shared Devise sender' do
      email = described_class.confirmation_instructions(user, 'confirm-token')

      expect(email[:from].value).to eq("Paul // Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>")
      expect(email[:reply_to].value).to eq("Paul // Dabble Me <hello@#{ENV['MAIN_DOMAIN']}>")
      body = email.html_part&.body&.decoded || email.body.decoded
      expect(body).to include('confirmation_token=confirm-token')
    end
  end
end
