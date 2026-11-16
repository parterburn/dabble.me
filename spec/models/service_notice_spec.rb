require 'rails_helper'

RSpec.describe ServiceNotice do
  let(:admin) { FactoryBot.create(:user, admin: true) }

  def writer(**attributes)
    FactoryBot.create(:user, **attributes).tap { |user| FactoryBot.create(:entry, user: user, body: 'text') }
  end

  describe '.recipients' do
    it 'is everyone with an entry, whatever their plan or email settings' do
      free = writer(plan: 'Free')
      pro = writer(plan: 'PRO Monthly PayHere')
      no_updates = writer(send_updates: false)
      no_prompts = writer(frequency: [])
      bounced = writer(emails_bounced: 3)
      FactoryBot.create(:user)

      expect(described_class.recipients).to contain_exactly(free, pro, no_updates, no_prompts, bounced)
    end

    it 'counts someone with many entries once' do
      prolific = writer
      FactoryBot.create(:entry, user: prolific, body: 'more', date: 2.days.ago)

      expect(described_class.recipients.count).to eq(1)
    end

    it 'leaves out an account that is being deleted' do
      writer(deleted_at: Time.current)

      expect(described_class.recipients).to be_empty
    end

    it 'leaves out someone who stopped notices in the last year, and brings them back after it' do
      stopped = writer
      notice = described_class.create!(sent_on: Date.current, created_at: 2.days.ago)
      delivery = ServiceNoticeDelivery.create!(service_notice: notice, user: stopped, created_at: 2.days.ago)
      expect(described_class.recipients).to contain_exactly(stopped)

      delivery.stop!
      expect(described_class.recipients).to be_empty

      delivery.update_columns(stopped_at: 13.months.ago)
      expect(described_class.recipients).to contain_exactly(stopped)
    end
  end

  describe 'the message' do
    it 'is optional, and a blank one is stored as nothing' do
      notice = described_class.new(message: "  \n ")

      expect(notice).to be_valid
      expect(notice.message).to be_nil
    end

    it 'can be as long as the limit and no longer' do
      expect(described_class.new(message: 'a' * described_class::MESSAGE_LIMIT)).to be_valid
      expect(described_class.new(message: 'a' * (described_class::MESSAGE_LIMIT + 1))).not_to be_valid
    end

    it 'counts a line break as one character, as the form does' do
      lines = (["a" * 99] * 20).join("\r\n")
      notice = described_class.new(message: lines)

      expect(lines.length).to be > described_class::MESSAGE_LIMIT
      expect(notice).to be_valid
      expect(notice.message).not_to include("\r")
    end

    it 'cannot carry a link' do
      ['See https://example.com', 'see HTTP://example.com/x', 'go to www.example.com'].each do |message|
        notice = described_class.new(message: message)

        expect(notice).not_to be_valid
        expect(notice.errors[:message].first).to include("can't contain links")
      end
    end
  end

  describe '.send_to_everyone!' do
    before { allow(ServiceNoticeJob).to receive(:perform_later) }

    it 'records who sent it and to how many, and queues the emails' do
      2.times { writer }

      notice = described_class.send_to_everyone!(message: 'We are closing.', sent_by: admin)

      expect(notice).to have_attributes(message: 'We are closing.', sent_by: admin, recipients_count: 2, sent_on: Time.current.utc.to_date)
      expect(ServiceNoticeJob).to have_received(:perform_later).with(notice.id)
    end

    it 'sends one notice a day, even when asked twice at once' do
      described_class.send_to_everyone!(message: nil, sent_by: admin)

      expect(described_class.send_to_everyone!(message: nil, sent_by: admin)).to be_nil
      expect(described_class.count).to eq(1)
      expect(ServiceNoticeJob).to have_received(:perform_later).once
    end

    it 'checks the 24 hours itself, so a send just after midnight UTC is refused too' do
      described_class.create!(sent_on: Time.current.utc.to_date - 1, created_at: 1.hour.ago)

      expect(described_class.send_to_everyone!(message: nil, sent_by: admin)).to be_nil
      expect(described_class.count).to eq(1)
      expect(ServiceNoticeJob).not_to have_received(:perform_later)
    end

    it 'records nothing when the emails cannot be queued, so it can be tried again' do
      allow(ServiceNoticeJob).to receive(:perform_later).and_raise(RuntimeError, 'queue is down')

      expect { described_class.send_to_everyone!(message: nil, sent_by: admin) }.to raise_error(described_class::NotQueued)
      expect(described_class.count).to eq(0)
      expect(described_class.blocker).to be_nil
    end
  end

  describe '.blocker' do
    it 'is nothing until a notice has gone out, then lasts 24 hours' do
      expect(described_class.blocker).to be_nil

      described_class.create!(sent_on: Date.new(2026, 3, 1), created_at: 23.hours.ago)
      expect(described_class.blocker).to include('The next one can be sent 24 hours after it.')

      described_class.update_all(created_at: 25.hours.ago)
      expect(described_class.blocker).to be_nil
    end
  end

  describe '#queue_deliveries!' do
    let(:notice) { described_class.create!(sent_on: Date.current, created_at: Time.current) }
    let(:queued) { [] }

    before do
      stub_const('ServiceNotice::BATCH_SIZE', 2)
      allow(ActiveJob).to receive(:perform_all_later) { |jobs| queued.concat(jobs) }
    end

    it 'queues a batch of people in one call, paced at PER_MINUTE, and says who' do
      first, second, _third = Array.new(3) { writer }
      now = Time.current

      expect(notice.queue_deliveries!).to eq([first.id, second.id])
      expect(ActiveJob).to have_received(:perform_all_later).once
      expect(queued.map(&:arguments)).to eq([[notice.id, first.id], [notice.id, second.id]])
      expect(queued.map { |job| (job.scheduled_at - now).round(1) }).to eq([0.0, 0.5])
    end

    it 'carries on after the last person queued, keeping the pace' do
      _first, second, third = Array.new(3) { writer }
      now = Time.current

      expect(notice.queue_deliveries!(after_id: second.id, offset: 2)).to eq([third.id])
      expect(queued.map(&:arguments)).to eq([[notice.id, third.id]])
      expect((queued.first.scheduled_at - now).round(1)).to eq(1.0)
    end

    it 'queues nothing when nobody is left' do
      expect(notice.queue_deliveries!).to eq([])
      expect(ActiveJob).not_to have_received(:perform_all_later)
    end
  end
end
