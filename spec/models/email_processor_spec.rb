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

    it "preserves a trailing Gmail-authored indentation block" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "First paragraph\n\n> Second intentionally indented paragraph",
        raw_html: '<div dir="ltr"><div>First paragraph</div><blockquote style="margin:0 0 0 40px;border:none;padding:0"><div>Second intentionally indented paragraph</div></blockquote></div>',
        vendor_specific: {
          stripped_html: '<div>First paragraph</div>'
        }
      )

      EmailProcessor.new(email).process

      expect(paid_user.entries.reload.first.body).to eq(
        '<div><div>First paragraph</div><blockquote><div>Second intentionally indented paragraph</div></blockquote></div>'
      )
    end

    it "preserves trailing Gmail-authored indentation for a free user as plain formatting" do
      user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "First paragraph\n\n> Second intentionally indented paragraph",
        raw_html: '<div dir="ltr"><div>First paragraph</div><blockquote style="margin:0 0 0 40px;border:none;padding:0"><div>Second intentionally indented paragraph</div></blockquote></div><div class="gmail_quote"><div>On Aug 2, 2026, Dabble Me wrote:</div><blockquote><div>Actual quoted history</div></blockquote></div>',
        vendor_specific: {
          stripped_html: '<div>First paragraph</div>'
        }
      )

      EmailProcessor.new(email).process

      expect(user.entries.reload.first.body).to eq(
        'First paragraph<br><br>Second intentionally indented paragraph'
      )
    end

    it "preserves a whole Gmail-authored indented entry with multiple quote lines" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "> First indented paragraph\n>\n> Second indented paragraph",
        raw_html: '<blockquote style="margin:0 0 0 40px;border:none;padding:0"><div>First indented paragraph</div><div><br></div><div>Second indented paragraph</div></blockquote>',
        vendor_specific: {
          stripped_html: nil
        }
      )

      EmailProcessor.new(email).process

      expect(paid_user.entries.reload.first.body).to eq(
        '<blockquote><div>First indented paragraph</div><br><div>Second indented paragraph</div></blockquote>'
      )
    end

    it "preserves normal text after a Gmail-authored indentation block" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "Before indentation\n\n> Intentionally indented\n\nAfter indentation",
        raw_html: '<div dir="ltr"><div>Before indentation</div><blockquote style="margin:0 0 0 40px;border:none;padding:0"><div>Intentionally indented</div></blockquote><div>After indentation</div></div>',
        vendor_specific: {
          stripped_html: '<div>Before indentation</div><div>After indentation</div>'
        }
      )

      EmailProcessor.new(email).process

      expect(paid_user.entries.reload.first.body).to eq(
        '<div><div>Before indentation</div><blockquote><div>Intentionally indented</div></blockquote><div>After indentation</div></div>'
      )
    end

    it "preserves authored indentation while excluding actual Gmail quote history" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "First paragraph\n\n> Authored indentation",
        raw_html: '<div dir="ltr"><div>First paragraph</div><blockquote style="margin:0 0 0 40px;border:none;padding:0"><div>Authored indentation</div></blockquote></div><div class="gmail_quote"><div>On Aug 2, 2026, Dabble Me wrote:</div><blockquote><div>Actual quoted history</div></blockquote></div>',
        vendor_specific: {
          stripped_html: '<div>First paragraph</div>'
        }
      )

      EmailProcessor.new(email).process

      saved_body = paid_user.entries.reload.first.body
      expect(saved_body).to eq(
        '<div><div>First paragraph</div><blockquote><div>Authored indentation</div></blockquote></div>'
      )
      expect(saved_body).not_to include('Actual quoted history')
      expect(saved_body).not_to include('Dabble Me wrote')
    end

    it "rejects a generic raw quote when an attribution reveals quoted history" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "New response\n\n> Previous entry",
        raw_html: '<div>New response</div><div>On Aug 2, 2026, Someone wrote:</div><blockquote><div>Previous entry</div></blockquote>',
        vendor_specific: {
          stripped_html: '<div>New response</div>'
        }
      )

      EmailProcessor.new(email).process

      expect(paid_user.entries.reload.first.body).to eq('<div>New response</div>')
    end

    it "falls back safely when raw indentation HTML contains active content" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "First paragraph\n\n> Second paragraph",
        raw_html: '<div>First paragraph</div><blockquote style="margin:0 0 0 40px;border:none;padding:0" onclick="alert(1)"><div>Second paragraph</div></blockquote>',
        vendor_specific: {
          stripped_html: '<div>First paragraph</div>'
        }
      )

      EmailProcessor.new(email).process

      saved_body = paid_user.entries.reload.first.body
      expect(saved_body).to eq('<div>First paragraph</div>')
      expect(saved_body).not_to include('onclick')
    end

    it "falls back safely when raw indentation text does not match the Griddler body" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "First paragraph\n\n> Expected second paragraph",
        raw_html: '<div>First paragraph</div><blockquote style="margin:0 0 0 40px;border:none;padding:0"><div>Different second paragraph</div></blockquote>',
        vendor_specific: {
          stripped_html: '<div>First paragraph</div>'
        }
      )

      EmailProcessor.new(email).process

      expect(paid_user.entries.reload.first.body).to eq('<div>First paragraph</div>')
    end

    it "keeps the complete plain fallback for #144 malformed authored content inside .gmail_quote" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "FIRST PARAGRAPH\n\nSECOND PARAGRAPH\n\nTHIRD PARAGRAPH with NBSP\n\nFOURTH PARAGRAPH with NBSP",
        raw_html: '<div dir="ltr"><div>FIRST PARAGRAPH<br><div class="gmail_quote"><div dir="ltr"><div class="gmail_quote"><div dir="ltr"><div><br></div><div>SECOND PARAGRAPH</div><div><br></div><div>THIRD PARAGRAPH with&nbsp;NBSP</div><div><br></div><div>FOURTH PARAGRAPH with&nbsp;NBSP</div></div></div></div></div></div><div><div dir="ltr" class="gmail_signature" data-smartmail="gmail_signature"><div dir="ltr"><div><br>--<br></div><div><b>Paul Arterburn</b></div></div></div></div></div>',
        vendor_specific: {
          stripped_html: '<div><div>FIRST PARAGRAPH</div></div>'
        }
      )

      EmailProcessor.new(email).process

      saved_body = paid_user.entries.reload.first.body
      expect(saved_body).to eq(
        '<div>FIRST PARAGRAPH<br><br>SECOND PARAGRAPH<br><br>THIRD PARAGRAPH with NBSP<br><br>FOURTH PARAGRAPH with NBSP</div>'
      )
      expect(saved_body.scan('<br><br>').size).to eq(3)
      expect(saved_body).not_to include('Paul Arterburn')
    end

    it "prefers complete stripped HTML for a normal paid entry" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "Complete rich reply",
        raw_html: "<div>Complete rich reply</div>",
        vendor_specific: {
          stripped_html: "<div>Complete <strong>rich</strong> reply</div>"
        }
      )

      EmailProcessor.new(email).process

      expect(paid_user.entries.reload.first.body).to eq("<div>Complete <strong>rich</strong> reply</div>")
    end

    it "rejects raw HTML with quoted history and preserves the complete plain reply" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "FIRST PARAGRAPH\n\nSECOND PARAGRAPH",
        raw_html: '<div>FIRST PARAGRAPH</div><div>SECOND PARAGRAPH</div><blockquote>QUOTED HISTORY</blockquote>',
        vendor_specific: {
          stripped_html: '<div>FIRST PARAGRAPH</div>'
        }
      )

      EmailProcessor.new(email).process

      expect(paid_user.entries.reload.first.body).to eq("<div>FIRST PARAGRAPH<br><br>SECOND PARAGRAPH</div>")
    end

    it "does not fall back to raw HTML when stripped HTML is truncated" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "FIRST PARAGRAPH\n\nSECOND PARAGRAPH",
        raw_html: '<div><strong>FIRST PARAGRAPH</strong></div><div>SECOND PARAGRAPH</div>',
        vendor_specific: {
          stripped_html: '<div>FIRST PARAGRAPH</div>'
        }
      )

      EmailProcessor.new(email).process

      expect(paid_user.entries.reload.first.body).to eq("<div>FIRST PARAGRAPH<br><br>SECOND PARAGRAPH</div>")
    end

    it "preserves the complete plain reply when raw HTML is unavailable" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "FIRST PARAGRAPH\n\nSECOND PARAGRAPH",
        vendor_specific: {
          stripped_html: '<div>FIRST PARAGRAPH</div>'
        }
      )

      EmailProcessor.new(email).process

      expect(paid_user.entries.reload.first.body).to eq("<div>FIRST PARAGRAPH<br><br>SECOND PARAGRAPH</div>")
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

    it "stores consistent separators from mixed Gmail paragraph markup" do
      paid_user.entries.destroy_all
      email = FactoryBot.build(
        :email,
        to: [{ token: paid_user.user_key, host: ENV['SMTP_DOMAIN'], email: "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}"}],
        body: "First paragraph\n\nSecond paragraph\n\nThird paragraph. Lorem ipsum\n\nFourth paragraph. Lorem ipsum",
        vendor_specific: {
          stripped_html: '<div>First paragraph<br></div><div>Second paragraph</div><div><br></div><div>Third paragraph.&nbsp;Lorem ipsum</div><div><br></div><div>Fourth paragraph.&nbsp;Lorem ipsum</div>'
        }
      )

      EmailProcessor.new(email).process

      expect(paid_user.entries.reload.first.body).to eq(
        '<div>First paragraph</div><br><div>Second paragraph</div><br><div>Third paragraph.&nbsp;Lorem ipsum</div><br><div>Fourth paragraph.&nbsp;Lorem ipsum</div>'
      )
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

    it 'normalizes mixed Gmail paragraph separators to one blank line' do
      html = '<div>First paragraph<br></div><div>Second paragraph</div><div><br></div><div>Third paragraph.&nbsp;Lorem ipsum</div><div><br></div><div>Fourth paragraph.&nbsp;Lorem ipsum</div>'

      expect(clean(html)).to eq('<div>First paragraph</div><br><div>Second paragraph</div><br><div>Third paragraph.&nbsp;Lorem ipsum</div><br><div>Fourth paragraph.&nbsp;Lorem ipsum</div>')
    end

    describe 'paragraph separator variants' do
      {
        'a trailing break in the preceding block' => [
          '<div>First<br></div><div>Second</div>',
          '<div>First</div><br><div>Second</div>'
        ],
        'a leading break in the following block' => [
          '<div>First</div><div><br>Second</div>',
          '<div>First</div><br><div>Second</div>'
        ],
        'an explicit break between blocks' => [
          '<div>First</div><br><div>Second</div>',
          '<div>First</div><br><div>Second</div>'
        ],
        'an empty div between blocks' => [
          '<div>First</div><div><br></div><div>Second</div>',
          '<div>First</div><br><div>Second</div>'
        ],
        'an NBSP-only paragraph between blocks' => [
          '<div>First</div><p>&nbsp;</p><div>Second</div>',
          '<div>First</div><br><div>Second</div>'
        ],
        'duplicate trailing and empty-block separators' => [
          '<div>First<br></div><div><br></div><div>Second</div>',
          '<div>First</div><br><div>Second</div>'
        ],
        'multiple trailing breaks' => [
          '<div>First<br><br></div><div>Second</div>',
          '<div>First</div><br><div>Second</div>'
        ],
        'multiple consecutive empty blocks' => [
          '<div>First</div><div><br></div><p>&nbsp;</p><div><br></div><div>Second</div>',
          '<div>First</div><br><div>Second</div>'
        ]
      }.each do |description, (html, expected)|
        it "normalizes #{description} to exactly one blank line" do
          expect(clean(html)).to eq(expected)
        end
      end

      it 'normalizes separators inside a Gmail wrapper' do
        html = '<div><div>First<br></div><div>Second</div><div><br></div><div>Third</div></div>'

        expect(clean(html)).to eq('<div><div>First</div><br><div>Second</div><br><div>Third</div></div>')
      end

      it 'does not invent a blank line between adjacent blocks' do
        expect(clean('<div>First</div><div>Second</div>')).to eq('<div>First</div><div>Second</div>')
      end

      it 'preserves a single authored line break within a paragraph' do
        expect(clean('<div>First line<br>Second line</div>')).to eq('<div>First line<br>Second line</div>')
      end
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
