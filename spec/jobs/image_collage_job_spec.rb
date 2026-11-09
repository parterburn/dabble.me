require 'rails_helper'

RSpec.describe ImageCollageJob, type: :job do
  include_context 'has all objects'
  include ActiveJob::TestHelper

  let(:message_id) { 'ABC-123@icloud.com' }

  describe '.perform_later_for_mailgun' do
    it 'waits for Mailgun to index the stored event before running' do
      # ActiveJob::TestHelper already installs a test adapter for this example.
      expect do
        described_class.perform_later_for_mailgun(paid_entry.id, message_id: message_id)
      end.to have_enqueued_job(described_class)
        .with(paid_entry.id, message_id: message_id)
        .at(a_value_within(1.second).of(described_class::MAILGUN_INDEX_DELAY.from_now))
    end
  end

  describe '.perform_later_for_mailgun with recipient_key' do
    it 'passes along the posting address the email was accepted on' do
      expect do
        described_class.perform_later_for_mailgun(paid_entry.id, message_id: message_id, recipient_key: paid_user.user_key)
      end.to have_enqueued_job(described_class).with(paid_entry.id, message_id: message_id, recipient_key: paid_user.user_key)
    end
  end

  describe '#message_from_user?' do
    let(:job) do
      described_class.new.tap do |j|
        j.instance_variable_set(:@user, paid_user)
        j.instance_variable_set(:@recipient_key, recipient_key)
      end
    end
    let(:recipient_key) { nil }
    let(:stranger) { 'someone@example.com' }

    context 'when the user resets their address after the email was accepted' do
      let(:recipient_key) { paid_user.user_key }

      it 'still accepts the stored message' do
        message = { 'recipients' => "#{recipient_key}@#{ENV['SMTP_DOMAIN']}", 'from' => stranger }
        paid_user.rotate_user_key!

        expect(job.send(:message_from_user?, message)).to be(true)
      end
    end

    it "accepts a message to the user's current address" do
      message = { 'recipients' => "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}", 'from' => stranger }

      expect(job.send(:message_from_user?, message)).to be(true)
    end

    it "rejects someone else's message" do
      message = { 'recipients' => "uotheruser12345678901@#{ENV['SMTP_DOMAIN']}", 'from' => stranger }

      expect(job.send(:message_from_user?, message)).to be(false)
    end
  end

  describe '#collage_from_mailgun_attachments' do
    it 'raises MailgunStoredEventNotFound when no stored event is found' do
      events_conn = instance_double(Faraday::Connection)
      empty_resp = instance_double(Faraday::Response, success?: true, status: 200, body: { 'items' => [] })
      allow(Faraday).to receive(:new).and_return(events_conn)
      allow(events_conn).to receive(:get).and_return(empty_resp)
      allow_any_instance_of(described_class).to receive(:sleep)

      job = described_class.new
      job.instance_variable_set(:@message_id, message_id)
      job.instance_variable_set(:@user, paid_user)

      expect do
        job.send(:collage_from_mailgun_attachments)
      end.to raise_error(described_class::MailgunStoredEventNotFound, /#{message_id}/)
    end
  end

  describe 'retry_on MailgunStoredEventNotFound' do
    it 're-enqueues with polynomial backoff instead of raising on wait calculation' do
      allow_any_instance_of(described_class).to receive(:collage_from_mailgun_attachments)
        .and_raise(described_class::MailgunStoredEventNotFound.new(message_id))

      described_class.perform_later(paid_entry.id, message_id: message_id)

      expect { perform_enqueued_jobs(only: described_class) }.not_to raise_error
      expect(enqueued_jobs.count { |job| job['job_class'] == described_class.name }).to eq(1)
    end
  end

  describe '.record_mailgun_lookup_failure' do
    before do
      allow(Sentry).to receive(:capture_message)
      allow(Sentry).to receive(:set_user)
      allow(EntryMailer).to receive_message_chain(:image_error, :deliver_later)
      allow(Rails.cache).to receive(:read).and_return(true)
    end

    it 'records the lookup failure after retries are exhausted' do
      error = described_class::MailgunStoredEventNotFound.new(message_id, lookup_log: [{ attempt: 0 }])
      job = described_class.new
      allow(job).to receive(:arguments).and_return([paid_entry.id, { message_id: message_id }])
      allow(job).to receive(:executions).and_return(described_class::MAILGUN_LOOKUP_JOB_ATTEMPTS)

      described_class.record_mailgun_lookup_failure(job, error)

      expect(Sentry).to have_received(:capture_message).with(
        'Mailgun events lookup failed for collage attachments',
        hash_including(
          level: :warning,
          extra: hash_including(
            message_id: message_id,
            lookup_attempts: [{ attempt: 0 }]
          )
        )
      )
      expect(paid_entry.reload.image_error).to eq("No last message found for message ID #{message_id}")
      expect(paid_entry).not_to be_uploading_image
    end
  end
end
