require 'rails_helper'

RSpec.describe NewsletterMailer do
  before { stub_const('Newsletter::ROOT', Rails.root.join('spec/fixtures/newsletters')) }

  let(:user) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere', first_name: 'Ann') }

  it 'sends the letter from hello@ with one-click unsubscribe and a footer' do
    mail = with_env('MAILING_ADDRESS' => '1 Main St, Denver, CO') { described_class.letter(user, 'sample', 'active').deliver_now }

    expect(mail.from).to eq(['hello@test'])
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq('Your 2026 in 0 entries')
    expect(mail.header['List-Unsubscribe'].value).to match(%r{\A<https?://[^>]+/updates/unsubscribe\?token=[^>]+>\z})
    expect(mail.header['List-Unsubscribe-Post'].value).to eq('List-Unsubscribe=One-Click')

    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    expect(html).to include('Hi Ann,', 'A look back.', 'your rewind', 'Unsubscribe from updates', '1 Main St, Denver, CO')
    expect(text).to include('Hi Ann,', 'Unsubscribe from updates: http', '1 Main St, Denver, CO')
    expect(text).not_to include('&amp;')
  end

  it 'sends from the app\'s usual address and Mailgun domain for PRO' do
    mail = described_class.letter(user, 'sample', 'quiet')

    expect(mail.reply_to).to be_nil
    expect(mail.delivery_method.settings[:domain]).not_to eq('updates.test')
    expect(mail.html_part.body.to_s).to include('you have a Dabble Me PRO account')
  end

  it 'sends free accounts their letter from the separate domain, with replies to the usual inbox' do
    free = FactoryBot.create(:user, plan: 'Free', first_name: 'Cy')
    mail = described_class.letter(free, 'sample', 'free')

    expect(mail.from).to eq(['hello@updates.test'])
    expect(mail.reply_to).to eq(['hello@test'])
    expect(mail.delivery_method.settings[:domain]).to eq('updates.test')
    expect(mail.subject).to eq('What is new, free')
    expect(mail.html_part.body.to_s).to include('you have a Dabble Me account')
    expect(mail.html_part.body.to_s).not_to include('PRO account')
  end

  it 'marks a preview in the subject' do
    mail = described_class.letter(user, 'sample', 'quiet', preview: true)
    expect(mail.subject).to eq('[Preview: quiet] What is new')
  end
end
