require 'rails_helper'

describe EmailProcessor do
  include_context 'has all objects'

  describe "#process" do
    it "creates an entry based on the email token" do
      user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "I am great"
      )

      EmailProcessor.new(email).process
      expect(user.entries.reload.first.body).to eq("I am great")
    end

    it "creates an entry from email if the token is wrong but email matches a user" do
      user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        from: ({ email: user.email }),
        to: [{ token: "WRONG", host: ENV['SMTP_DOMAIN'], email: "WRONG@#{ENV['SMTP_DOMAIN']}"}],
        body: "I am great"
      )

      EmailProcessor.new(email).process
      expect(user.entries.reload.first.body).to eq("I am great")
    end

    it "creates an more complex entry based on the email token for free user" do
      user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "I am great\n\nHere's a link: <a href=\"https://www.google.com\" target=\"_blank\">https://www.google.com</a>"
      )

      EmailProcessor.new(email).process
      expect(user.entries.reload.first.body).to eq("I am great<br><br>Here's a link: https://www.google.com")
    end

    it "creates an more complex HTML entry based on the email token for paid user" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "I am great\n\nHere's a link: https://www.google.com",
        vendor_specific: {
          stripped_html: "<p>I am great</p>\n\n<p>Here's a link: <a href=\"https://www.google.com\">https://www.google.com</a></p>"
        }
      )

      EmailProcessor.new(email).process
      expect(paid_user.entries.reload.first.body).to eq("<p>I am great</p><p>Here's a link: <a href=\"https://www.google.com\" target=\"_blank\">https://www.google.com</a></p>")
    end

    it "preserves blank lines between HTML email paragraphs" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "Blah blah blah. Blah blah.\n\nBlah blah blah. Blah!",
        vendor_specific: {
          stripped_html: "<div>Blah blah blah. Blah blah.</div><div><br></div><div>Blah blah blah. Blah!</div>"
        }
      )

      EmailProcessor.new(email).process
      expect(paid_user.entries.reload.first.body).to eq("<div>Blah blah blah. Blah blah.</div><br><div>Blah blah blah. Blah!</div>")
    end

    it "removes a trailing em-dash separator followed by a signature line" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "Today was good",
        vendor_specific: {
          stripped_html: "<div>Today was good</div><div>—</div><div>Someone here</div>"
        }
      )

      EmailProcessor.new(email).process
      expect(paid_user.entries.reload.first.body).to eq("<div>Today was good</div>")
    end

    it "removes a trailing em-dash separator followed by a signature line from free plain text email" do
      user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "Today was good\n\n—\n\nSomeone here"
      )

      EmailProcessor.new(email).process
      expect(user.entries.reload.first.body).to eq("Today was good")
    end

    it "removes a trailing Sent from my iPhone signature from paid html email" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "Today was good",
        vendor_specific: {
          stripped_html: "<div>Today was good</div><div>Sent from my iPhone</div>"
        }
      )

      EmailProcessor.new(email).process
      expect(paid_user.entries.reload.first.body).to eq("<div>Today was good</div>")
    end

    it "removes a trailing Sent from my iPhone signature from free plain text email" do
      user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "Today was good\n\nSent from my iPhone"
      )

      EmailProcessor.new(email).process
      expect(user.entries.reload.first.body).to eq("Today was good")
    end
  end

  describe '#clean_html_version' do
    subject(:clean_html) { described_class.allocate }

    def clean(html)
      clean_html.send(:clean_html_version, html)
    end

    it 'does not turn source formatting whitespace between blocks into breaks' do
      html = "<div>First</div>\n\n<div>Second</div>\n<p>Third</p>"

      expect(clean(html)).to eq('<div>First</div><div>Second</div><p>Third</p>')
    end

    it 'turns authored newlines inside text into breaks' do
      expect(clean("<div>First\nSecond\\nThird</div>")).to eq('<div>First<br>Second<br>Third</div>')
    end

    it 'collapses internal empty block runs to one blank line' do
      html = '<div>First</div><div><br></div><p>&nbsp;</p><div>Second</div>'

      expect(clean(html)).to eq('<div>First</div><br><div>Second</div>')
    end

    it 'removes leading and trailing empty blocks' do
      html = '<p><br></p><div>Content</div><p>&nbsp;</p>'

      expect(clean(html)).to eq('<div>Content</div>')
    end

    it 'preserves whitespace between inline elements' do
      html = "<div><strong>First</strong>\n<span>Second</span></div>"

      expect(clean(html)).to eq('<div><strong>First</strong> <span>Second</span></div>')
    end

    it 'does not turn pretty-printing around inline elements into breaks' do
      html = "<div>\n  First\n  <strong>Second</strong>\n  <span>Third</span>\n</div>"

      expect(clean(html)).to eq('<div>First <strong>Second</strong> <span>Third</span></div>')
    end

    it 'removes a Gmail signature before sanitization strips its marker' do
      html = '<div>Content</div><br id="lineBreakAtBeginningOfSignature"><div>Signature</div>'

      expect(clean(html)).to eq('<div>Content</div>')
    end

    it 'removes a signature preceded by an empty block' do
      html = '<div>Content</div><div><br></div><div>--</div><div>Signature</div>'

      expect(clean(html)).to eq('<div>Content</div>')
    end
  end
end
