require 'rails_helper'

RSpec.describe ServiceNoticeJob do
  let(:notice) { ServiceNotice.create!(sent_on: Date.current, created_at: Time.current) }

  def writer
    FactoryBot.create(:user).tap { |user| FactoryBot.create(:entry, user: user, body: 'text') }
  end

  before do
    stub_const('ServiceNotice::BATCH_SIZE', 2)
    allow(ActiveJob).to receive(:perform_all_later)
    allow(described_class).to receive(:perform_later)
  end

  it 'queues one batch and hands the rest to the next job' do
    _first, second, _third = Array.new(3) { writer }

    described_class.perform_now(notice.id)

    expect(ActiveJob).to have_received(:perform_all_later).once
    expect(described_class).to have_received(:perform_later).with(notice.id, second.id, 2)
  end

  it 'stops after the last batch' do
    _first, second, _third = Array.new(3) { writer }

    described_class.perform_now(notice.id, second.id, 2)

    expect(ActiveJob).to have_received(:perform_all_later).once
    expect(described_class).not_to have_received(:perform_later)
  end

  it 'does nothing for a notice that is gone' do
    expect { described_class.perform_now(0) }.not_to raise_error
    expect(ActiveJob).not_to have_received(:perform_all_later)
  end
end
