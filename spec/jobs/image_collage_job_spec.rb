require 'rails_helper'

RSpec.describe ImageCollageJob, type: :job do
  include_context 'has all objects'

  let(:message_id) { 'ABC-123@icloud.com' }

  describe '#perform' do
    before do
      allow(Sentry).to receive(:capture_message)
      allow(Sentry).to receive(:set_user)
      allow(EntryMailer).to receive_message_chain(:image_error, :deliver_later)
      allow(Rails.cache).to receive(:read).and_return(true)
    end

    it 'logs mailgun lookup diagnostics when no stored event is found' do
      events_conn = instance_double(Faraday::Connection)
      empty_resp = instance_double(Faraday::Response, success?: true, status: 200, body: { 'items' => [] })
      allow(Faraday).to receive(:new).and_return(events_conn)
      allow(events_conn).to receive(:get).and_return(empty_resp)
      allow_any_instance_of(described_class).to receive(:sleep)

      described_class.perform_now(paid_entry.id, message_id: message_id)

      expect(Sentry).to have_received(:capture_message).with(
        'Mailgun events lookup failed for collage attachments',
        hash_including(
          level: :warning,
          extra: hash_including(
            message_id: message_id,
            lookup_attempts: be_present
          )
        )
      )
      expect(paid_entry.reload.image_error).to eq('No last message found')
    end
  end
end
