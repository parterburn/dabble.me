require 'rails_helper'

RSpec.describe Newsletter do
  before { stub_const('Newsletter::ROOT', Rails.root.join('spec/fixtures/newsletters')) }

  let(:newsletter) { Newsletter.find('sample') }
  let(:pro) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere', first_name: 'Ann') }

  def write_entries(user, count, year: 2026)
    count.times { |day| FactoryBot.create(:entry, user: user, body: 'text', date: Time.utc(year, 3, day + 1, 12)) }
  end

  it 'refuses names that are not plain folder names' do
    expect { Newsletter.find('../config') }.to raise_error(Newsletter::Error)
    expect { Newsletter.find('missing') }.to raise_error(Newsletter::Error, /No newsletter/)
  end

  it 'gives each person the first letter they qualify for, counting only that year' do
    write_entries(pro, 2)
    quiet = FactoryBot.create(:user, plan: 'PRO Yearly PayHere')
    write_entries(quiet, 1)
    write_entries(quiet, 4, year: 2025)

    expect(newsletter.variant_for(pro)).to eq('active')
    expect(newsletter.variant_for(quiet)).to eq('quiet')
  end

  it 'goes to PRO accounts that still take updates' do
    opted_out = FactoryBot.create(:user, plan: 'PRO Monthly PayHere', send_updates: false)
    deleted = FactoryBot.create(:user, plan: 'PRO Monthly PayHere', deleted_at: Time.current)
    no_prompts = FactoryBot.create(:user, plan: 'PRO Forever', frequency: [])

    expect(newsletter.audience('pro')).to contain_exactly(pro, no_prompts)
    expect(newsletter.recipient?(opted_out)).to be(false)
    expect(newsletter.recipient?(deleted)).to be(false)
  end

  it 'goes to free accounts that were active lately and never bounced' do
    signed_in = FactoryBot.create(:user, plan: 'Free', last_sign_in_at: 2.months.ago)
    wrote = FactoryBot.create(:user, plan: nil)
    FactoryBot.create(:entry, user: wrote, body: 'text', date: 3.months.ago)
    FactoryBot.create(:user, plan: 'Free', last_sign_in_at: 3.years.ago)
    FactoryBot.create(:user, plan: 'Free')
    FactoryBot.create(:user, plan: 'Free', last_sign_in_at: 1.month.ago, emails_bounced: 2)
    FactoryBot.create(:user, plan: 'Free', last_sign_in_at: 1.month.ago, send_updates: false)

    expect(newsletter.audience('free')).to contain_exactly(signed_in, wrote)
    expect(newsletter.variant_for(signed_in)).to eq('free')
    expect(newsletter.recipient?(signed_in)).to be(true)
    expect(newsletter.recipient?(pro)).to be(true)
  end

  it 'refuses a newsletter whose variants leave someone without a letter' do
    directory = Pathname(Dir.mktmpdir)
    directory.join('letter.md').write("---\nsubject: Hi\n---\n\nBody\n")
    directory.join('newsletter.yml').write({ 'year' => 2026, 'audiences' => { 'pro' => {}, 'free' => {} },
                                             'variants' => [{ 'name' => 'only', 'plan' => 'pro' }] }.to_yaml)

    expect { described_class.new('broken', directory) }.to raise_error(Newsletter::Error, /free needs a variant/)
  end

  describe Newsletter::Letter do
    it 'fills placeholders, keeps only the blocks for the variant, and renders HTML and plain text' do
      write_entries(pro, 3)
      rendered = newsletter.letter.render(newsletter.values_for(pro), variant: 'active')

      expect(rendered.subject).to eq('Your 2026 in 3 entries')
      expect(rendered.preview).to eq('A look back.')
      expect(rendered.html).to include('Hi Ann,', '<a href="https://test/rewind/2026">your rewind</a>', 'Here is what is new.', '<h2>Thanks</h2>', '<li>one</li>')
      expect(rendered.html).not_to include('when you like', '{{')
      expect(rendered.text).to include('See your rewind (https://test/rewind/2026).', "Thanks\n", '- one')
      expect(rendered.text).not_to include('**', '##')
    end

    it 'gives the other variant its own subject and blocks, with no gap where one was dropped' do
      rendered = newsletter.letter.render(newsletter.values_for(pro), variant: 'quiet')

      expect(rendered.subject).to eq('What is new')
      expect(rendered.markdown).to start_with("Hi Ann,\n\nHere is what is new.\n\n[Write](https://test/write) when you like.\n\n## Thanks")
      expect(rendered.html).not_to include('your rewind')
    end

    it 'greets someone with no first name' do
      nameless = FactoryBot.create(:user, plan: 'PRO Monthly PayHere', first_name: nil)
      expect(newsletter.letter.render(newsletter.values_for(nameless), variant: 'quiet').html).to include('Hi there,')
    end

    it 'fails on a placeholder nothing fills' do
      expect { newsletter.letter.render({ 'first_name' => 'Ann' }, variant: 'active') }.to raise_error(Newsletter::Error, /nothing fills/)
    end

    def letter_from(text)
      path = Pathname(Dir.mktmpdir).join('letter.md')
      path.write(text)
      described_class.new(path, %w[active quiet])
    end

    it 'refuses a block that names no variant, or is left open' do
      expect { letter_from("---\nsubject: Hi\n---\n\n{{#actve}}\nx\n{{/actve}}\n") }.to raise_error(Newsletter::Error, /names no variant/)
      expect { letter_from("---\nsubject: Hi\n---\n\n{{#active}}\nx\n") }.to raise_error(Newsletter::Error, /no matching line/)
    end

    it 'refuses a subject that misses a variant' do
      expect { letter_from("---\nsubject:\n  active: Hi\n---\n\nBody\n") }.to raise_error(Newsletter::Error, /every variant/)
    end
  end

  describe Newsletter::Send do
    let(:send) { Newsletter::Send.new(newsletter) }
    let!(:active) { pro.tap { |user| write_entries(user, 2) } }
    let!(:quiet) { FactoryBot.create(:user, plan: 'PRO Yearly PayHere') }
    let!(:free) { FactoryBot.create(:user, plan: 'Free', last_sign_in_at: 1.week.ago) }
    let!(:lapsed) { FactoryBot.create(:user, plan: 'Free', last_sign_in_at: 4.years.ago) }

    around do |example|
      with_env('MAILING_ADDRESS' => '1 Main St, Denver, CO') { example.run }
    end

    it 'plans who gets which letter and skips people already sent' do
      expect(send.plan).to eq('active' => [active.id], 'quiet' => [quiet.id], 'free' => [free.id])

      NewsletterDelivery.create!(user: active, newsletter: 'sample', variant: 'active', created_at: Time.current)
      again = Newsletter::Send.new(newsletter)
      expect(again.plan).to eq('active' => [], 'quiet' => [quiet.id], 'free' => [free.id])
      expect(again.already_delivered).to eq(1)
    end

    it 'can be limited to one plan and to a number of emails' do
      expect(Newsletter::Send.new(newsletter, plan: 'free').plan).to eq('free' => [free.id])
      expect(Newsletter::Send.new(newsletter, plan: 'pro').queue).to eq([active.id, quiet.id])
      expect(Newsletter::Send.new(newsletter, limit: 2).queue).to eq([active.id, quiet.id])
    end

    it 'queues one spaced-out job per person' do
      queued = []
      allow(NewsletterDeliveryJob).to receive(:set) do |wait:|
        double(perform_later: nil).tap { |job| allow(job).to receive(:perform_later) { |*args| queued << [wait, *args] } }
      end

      expect(send.deliver!(per_minute: 60)).to eq(3)
      expect(queued).to eq([[0.seconds, active.id, 'sample'], [1.second, quiet.id, 'sample'], [2.seconds, free.id, 'sample']])
    end

    it 'will not send without a postal address' do
      with_env('MAILING_ADDRESS' => nil) do
        expect(send.blockers).to include(/MAILING_ADDRESS/)
        expect { send.deliver!(per_minute: 60) }.to raise_error(Newsletter::Error)
      end
    end
  end

  it 'writes the 2026 Rewind with the entry count for writers and without the Rewind for everyone else' do
    stub_const('Newsletter::ROOT', Rails.root.join('newsletters'))
    rewind = described_class.find('2026-rewind')
    write_entries(pro, 20)
    opening = "Dabble Me turned twelve this year, and it changed more in 2026 than in the previous several years combined.\n\n" \
              "I built it for my wife and me, and I keep building the things that keep me journaling, because I know how much a journal is worth. Here is what's new."

    writer = rewind.letter.render(rewind.values_for(pro), variant: rewind.variant_for(pro))
    expect(writer.subject).to eq('Your 2026 Rewind is ready')
    expect(writer.text).to include('You wrote 20 entries in 2026, and your Rewind is ready: dabble.me/rewind/2026 (https://test/rewind/2026)', opening)

    other = FactoryBot.create(:user, plan: 'PRO Forever', first_name: 'Bo')
    quiet = rewind.letter.render(rewind.values_for(other), variant: rewind.variant_for(other))
    expect(quiet.subject).to eq("What's new in Dabble Me")
    expect(quiet.markdown).to start_with("Hi Bo,\n\n#{opening}\n\nSee it for yourself: **[write a line about today](https://test/write)**. One sentence counts.\n\n## An iPhone app")
    expect(quiet.text).not_to include('Rewind is ready', 'You wrote', 'Subscribe to PRO')

    free_writer = FactoryBot.create(:user, plan: 'Free', first_name: 'Cy')
    write_entries(free_writer, 6)
    waiting = rewind.letter.render(rewind.values_for(free_writer), variant: rewind.variant_for(free_writer))
    expect(waiting.subject).to eq('Your 2026 Rewind is waiting')
    expect(waiting.text).to include('You wrote 6 entries in 2026, and your Rewind is waiting:', 'PRO unlocks the rest (https://test/subscribe)',
                                    opening, 'PRO is $4 a month or $40 a year.', 'Subscribe to PRO (https://test/subscribe)')
    expect(waiting.text).not_to include('Rewind is ready', 'See it for yourself')

    free_quiet = FactoryBot.create(:user, plan: 'Free', first_name: 'Di')
    plain = rewind.letter.render(rewind.values_for(free_quiet), variant: rewind.variant_for(free_quiet))
    expect(plain.subject).to eq("What's new in Dabble Me")
    expect(plain.text).to include('See it for yourself: write a line about today (https://test/write)', 'Subscribe to PRO (https://test/subscribe)')
    expect(plain.text).not_to include('You wrote')
    letters = [writer, quiet, waiting, plain]
    expect(rewind.letter).not_to be_unfinished

    letters.each do |letter|
      expect(letter.text).not_to match(/\bbeta\b|MCP|end-to-end/i)
      expect(letter.html).to include('<a href="https://testflight.apple.com/join/mYj4vrFZ">Get the app</a>')
      expect(letter.html).to include('Paul Arterburn<br>', 'founder/maker of dabble.me<br>', '<a href="https://x.com/parterburn">x.com/parterburn</a>')
      expect(letter.text).to end_with("Paul Arterburn\nfounder/maker of dabble.me\nx.com/parterburn (https://x.com/parterburn)")
    end
  end

  describe 'the newsletters in this repository' do
    before { stub_const('Newsletter::ROOT', Rails.root.join('newsletters')) }

    Rails.root.join('newsletters').children.select(&:directory?).each do |directory|
      it "#{directory.basename} loads and every letter renders" do
        real = Newsletter.find(directory.basename.to_s)
        real.variants.each do |variant|
          rendered = real.letter.render(real.values_for(pro), variant: variant.name)
          expect(rendered.subject).to be_present
          expect(rendered.html).to include('Hi Ann,')
          expect(rendered.html).not_to include('{{')
        end
      end
    end
  end
end
