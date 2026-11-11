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
    free = FactoryBot.create(:user, plan: 'Free')
    opted_out = FactoryBot.create(:user, plan: 'PRO Monthly PayHere', send_updates: false)
    deleted = FactoryBot.create(:user, plan: 'PRO Monthly PayHere', deleted_at: Time.current)
    no_prompts = FactoryBot.create(:user, plan: 'PRO Forever', frequency: [])

    expect(newsletter.audience).to contain_exactly(pro, no_prompts)
    expect(newsletter.recipient?(free)).to be(false)
    expect(newsletter.recipient?(opted_out)).to be(false)
    expect(newsletter.recipient?(deleted)).to be(false)
  end

  describe Newsletter::Letter do
    it 'fills placeholders and renders HTML and plain text' do
      write_entries(pro, 3)
      rendered = newsletter.letter('active').render(newsletter.values_for(pro))

      expect(rendered.subject).to eq('Your 2026 in 3 entries')
      expect(rendered.preview).to eq('A look back.')
      expect(rendered.html).to include('Hi Ann,', '<a href="https://test/rewind/2026">your rewind</a>', '<h2>Thanks</h2>', '<li>one</li>')
      expect(rendered.text).to include('See your rewind (https://test/rewind/2026).', "Thanks\n", '- one')
      expect(rendered.text).not_to include('**', '##')
    end

    it 'greets someone with no first name' do
      nameless = FactoryBot.create(:user, plan: 'PRO Monthly PayHere', first_name: nil)
      expect(newsletter.letter('quiet').render(newsletter.values_for(nameless)).html).to include('Hi there,')
    end

    it 'fails on a placeholder nothing fills' do
      expect { newsletter.letter('active').render('first_name' => 'Ann') }.to raise_error(Newsletter::Error, /nothing fills/)
    end
  end

  describe Newsletter::Send do
    let(:send) { Newsletter::Send.new(newsletter) }
    let!(:active) { pro.tap { |user| write_entries(user, 2) } }
    let!(:quiet) { FactoryBot.create(:user, plan: 'PRO Yearly PayHere') }
    let!(:free) { FactoryBot.create(:user, plan: 'Free') }

    around do |example|
      with_env('MAILING_ADDRESS' => '1 Main St, Denver, CO') { example.run }
    end

    it 'plans who gets which letter and skips people already sent' do
      expect(send.plan).to eq('active' => [active.id], 'quiet' => [quiet.id])

      NewsletterDelivery.create!(user: active, newsletter: 'sample', variant: 'active', created_at: Time.current)
      again = Newsletter::Send.new(newsletter)
      expect(again.plan).to eq('active' => [], 'quiet' => [quiet.id])
      expect(again.already_delivered).to eq(1)
    end

    it 'queues one spaced-out job per person' do
      queued = []
      allow(NewsletterDeliveryJob).to receive(:set) do |wait:|
        double(perform_later: nil).tap { |job| allow(job).to receive(:perform_later) { |*args| queued << [wait, *args] } }
      end

      expect(send.deliver!(per_minute: 60)).to eq(2)
      expect(queued).to eq([[0.seconds, active.id, 'sample'], [1.second, quiet.id, 'sample']])
    end

    it 'will not send without a postal address' do
      with_env('MAILING_ADDRESS' => nil) do
        expect(send.blockers).to include(/MAILING_ADDRESS/)
        expect { send.deliver!(per_minute: 60) }.to raise_error(Newsletter::Error)
      end
    end
  end

  describe 'the newsletters in this repository' do
    before { stub_const('Newsletter::ROOT', Rails.root.join('newsletters')) }

    Rails.root.join('newsletters').children.select(&:directory?).each do |directory|
      it "#{directory.basename} loads and every letter renders" do
        real = Newsletter.find(directory.basename.to_s)
        real.variants.each do |variant|
          rendered = real.letter(variant.name).render(real.values_for(pro))
          expect(rendered.subject).to be_present
          expect(rendered.html).to include('Hi Ann,')
          expect(rendered.html).not_to include('{{')
        end
      end
    end
  end
end
