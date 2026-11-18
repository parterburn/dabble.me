require 'rails_helper'

RSpec.describe ServiceNoticeMailer do
  let(:user) { FactoryBot.create(:user, first_name: 'Ann') }

  it 'reminds the person to export, from hello@, without tracking or an unsubscribe link' do
    mail = described_class.export_reminder(user).deliver_now

    expect(mail.from).to eq(['hello@test'])
    expect(mail[:from].value).to eq('Dabble Me Support <hello@test>')
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq('Export your Dabble Me journal')
    expect(mail.mailgun_options).to include(tag: 'Service notice', tracking: 'no')
    expect(mail.header['List-Unsubscribe']).to be_nil

    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    expect(html).to include('Hey Ann,', 'keep a copy of your Dabble Me journal', '/entries/export"', "not a newsletter")
    expect(text).to include('Hey Ann,', 'Export your journal: http', '/entries/export', "not a newsletter")
    expect(html).not_to include('Stop further notices')
  end

  it "puts the admin's message under the greeting, as plain text with its line breaks" do
    message = "Dabble Me closes on March 1.\nYour journal is deleted 30 days later.\n\nThank you & goodbye <b>all</b>."
    mail = described_class.export_reminder(user, message: message).deliver_now

    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    expect(html).to include("<p>Dabble Me closes on March 1.\n<br />Your journal is deleted 30 days later.</p>")
    expect(html).to include('<p>Thank you &amp; goodbye &lt;b&gt;all&lt;/b&gt;.</p>')
    expect(html.index('Hey Ann,')).to be < html.index('Dabble Me closes')
    expect(html.index('Dabble Me closes')).to be < html.index('keep a copy')
    expect(text).to include("Hey Ann,\n\n#{message}\n\nThis is a reminder")
  end

  it 'says nothing extra without a message' do
    text = described_class.export_reminder(user, message: '  ').deliver_now.text_part.body.to_s

    expect(text).to include("Hey Ann,\n\nThis is a reminder")
  end

  it "links a person's own copy to the page that stops further notices, for one-click unsubscribe" do
    notice = ServiceNotice.create!(sent_on: Date.current, created_at: Time.current)
    delivery = ServiceNoticeDelivery.create!(service_notice: notice, user: user, created_at: Time.current)
    mail = described_class.export_reminder(user, delivery: delivery).deliver_now

    stop_url = mail.header['List-Unsubscribe'].value[/\A<(.+)>\z/, 1]
    expect(stop_url).to match(%r{\Ahttps?://[^/]+/notices/stop\?token=.+})
    expect(mail.header['List-Unsubscribe-Post'].value).to eq('List-Unsubscribe=One-Click')
    expect(mail.html_part.body.to_s).to include('Stop further notices like this one')
    expect(mail.text_part.body.to_s).to include("Stop further notices like this one: #{stop_url}")
    expect(ServiceNoticeDelivery.find_by_stop_token(Rack::Utils.parse_query(URI(stop_url).query)['token'])).to eq(delivery)
  end

  it 'marks a preview in the subject' do
    expect(described_class.export_reminder(user, preview: true).subject).to eq('[Preview] Export your Dabble Me journal')
  end
end
