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

  describe '#collage_from_mailgun_attachments with ignored images' do
    it "leaves out attachments the user's rules ignore and does not put the API key in a URL" do
      logo = signature_logo.pngsave_buffer
      IgnoredEmailImage.new(user: paid_user, kind: "filename").tap { |rule| rule.value = "b_logo.png" }.save!
      allow(CollageGenerator).to receive(:fetch).and_return(stored_copy(logo))
      IgnoredEmailImage.new(user: paid_user, kind: "image").tap { |rule| rule.value = "https://cdn.example.com/sig.jpg" }.save!

      original_key = ENV["MAILGUN_API_KEY"]
      ENV["MAILGUN_API_KEY"] = "key-secret-12345"
      photo = jpeg_bytes(photo_like(1))
      attachment = ->(id, name, type = "image/jpeg") { { "content-type" => type, "size" => 50_000, "name" => name, "url" => "https://storage.mailgun.net/#{id}" } }
      message = {
        "recipients" => "#{paid_user.user_key}@#{ENV['SMTP_DOMAIN']}",
        "attachments" => [attachment.("a1", "B_Logo.png", "image/png"), attachment.("a2", "IMG_1.jpg"), attachment.("a3", "IMG_2.jpg"), attachment.("a4", "image003.png", "image/png")]
      }
      allow(MailgunStorageClient).to receive(:get) do |url|
        body = if url.include?("/v3/messages/abc")
          message.to_json
        elsif url.end_with?("/a4")
          logo
        else
          photo
        end
        MailgunStorageClient::Response.new(body: body, status: 200, content_type: "image/jpeg")
      end

      job = described_class.new
      job.instance_variable_set(:@message_id, message_id)
      job.instance_variable_set(:@user, paid_user)
      allow(job).to receive(:fetch_mailgun_stored_event).and_return([{ "storage" => { "url" => "https://storage.mailgun.net/v3/messages/abc" } }, []])
      allow(job).to receive(:publish_bytes) { |_body, filename| "https://owned.example/#{filename}" }
      allow(job).to receive(:collage_from_urls) { |urls| urls }

      urls = job.send(:collage_from_mailgun_attachments)

      expect(urls.compact).to eq(%w[https://owned.example/IMG_1.jpg https://owned.example/IMG_2.jpg])
      expect(urls.join).not_to include("key-secret-12345")
      expect(urls.join).not_to include("@")
      expect(MailgunStorageClient).to have_received(:get).with("https://storage.mailgun.net/a2")
      expect(MailgunStorageClient).not_to have_received(:get).with(a_string_including("key-secret-12345"))
    ensure
      ENV["MAILGUN_API_KEY"] = original_key
    end
  end

  describe "#collage_from_urls HEIC" do
    it "downloads through SafeRemoteFetch and does not use URI.open" do
      job = described_class.new
      job.instance_variable_set(:@user, paid_user)
      fetched = SafeRemoteFetch::Result.new(body: "heic-bytes", content_type: "image/heic", final_url: "https://cdn.example.com/pic.heic")
      allow(SafeRemoteFetch).to receive(:fetch).and_return(fetched)
      expect(URI).not_to receive(:open)
      converter = instance_double(ImageConverter, tmp_s3_url: "https://owned.example/converted.jpg")
      allow(ImageConverter).to receive(:new).and_return(converter)

      url = job.send(:collage_from_urls, ["https://cdn.example.com/pic.heic"])

      expect(url).to eq("https://owned.example/converted.jpg")
      expect(SafeRemoteFetch).to have_received(:fetch).with("https://cdn.example.com/pic.heic", hash_including(:open_timeout, :read_timeout))
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
