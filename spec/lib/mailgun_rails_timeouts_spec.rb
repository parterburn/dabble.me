require 'rails_helper'

RSpec.describe MailgunRails::Client do
  describe '#send_message' do
    it 'uses explicit RestClient timeouts' do
      expect(RestClient::Request).to receive(:execute).with(
        hash_including(
          open_timeout: described_class::OPEN_TIMEOUT,
          read_timeout: described_class::READ_TIMEOUT
        )
      )

      described_class.new('api-key', 'example.com').send_message({})
    end
  end
end
