require 'rails_helper'

RSpec.describe SendHourlyEntriesWorker do
  it 'sends no journal emails once Dabble Me has closed' do
    SiteClosure.announce(closes_on: SiteClosure.today, announced_by: nil).update_columns(closes_on: SiteClosure.today - 1)
    expect(User).not_to receive(:subscribed_to_emails)

    described_class.new.perform
  end

  it 'keeps sending through the last day' do
    SiteClosure.announce(closes_on: SiteClosure.today, announced_by: nil)
    expect(User).to receive(:subscribed_to_emails).and_call_original

    described_class.new.perform
  end

  describe 'free accounts' do
    let(:worker) { described_class.new }
    let(:free_user) { double('user', is_pro?: false, is_free?: true, emails_sent: 7, entries: double(count: 0)) }

    # FREE_WEEK used to lift these limits; it's gone, so a stray env var changes nothing.
    around do |example|
      ENV['FREE_WEEK'] = 'true'
      example.run
    ensure
      ENV.delete('FREE_WEEK')
    end

    it 'sends only on even-numbered weeks' do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 1, 4, 12)) # week 01
      expect(worker.send(:eligible_to_send?, free_user)).to be(false)

      allow(Time).to receive(:now).and_return(Time.utc(2026, 1, 11, 12)) # week 02
      expect(worker.send(:eligible_to_send?, free_user)).to be(true)
    end

    it 'stops emailing after 6 emails with no entries' do
      expect(worker.send(:disable_free_user?, free_user)).to be(true)
    end
  end
end
