require 'rails_helper'

RSpec.describe Entry::AiTagger do
  let(:entry) { FactoryBot.create(:entry, body: 'Got the job offer today and I cannot stop smiling!') }
  let(:responses_url) { 'https://api.openai.com/v1/responses' }

  def stub_openai(emotions: nil, status: 200, body: nil)
    body ||= {
      output: [
        { type: 'reasoning', summary: [] },
        { type: 'message', content: [{ type: 'output_text', text: { emotions: emotions }.to_json }] }
      ]
    }
    stub_request(:post, responses_url).to_return(
      status: status,
      body: body.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  before { allow(Sentry).to receive(:capture_message) }

  it 'tags the entry with the emotions returned by OpenAI' do
    stub_openai(emotions: %w[joy surprise])

    described_class.new.tag([entry.id])

    expect(entry.reload.sentiment).to eq(%w[joy surprise])
  end

  it 'requests a strict json_schema limited to the known emotions' do
    stub_openai(emotions: ['joy'])

    described_class.new.tag([entry.id])

    expect(
      a_request(:post, responses_url).with do |req|
        params = JSON.parse(req.body)
        format = params.dig('text', 'format')
        params['model'] == 'gpt-6-luna' &&
          format['type'] == 'json_schema' &&
          format['strict'] == true &&
          format.dig('schema', 'properties', 'emotions', 'items', 'enum') == (described_class::EMOTIONS.keys - ['unknown'])
      end
    ).to have_been_made.once
  end

  it 'drops neutral when other emotions are present and caps the count' do
    stub_openai(emotions: %w[neutral sadness fear anger])

    described_class.new.tag([entry.id])

    expect(entry.reload.sentiment).to eq(%w[sadness fear])
  end

  it 'tags as unknown when no emotions are returned' do
    stub_openai(emotions: [])

    described_class.new.tag([entry.id])

    expect(entry.reload.sentiment).to eq(['unknown'])
  end

  it 'leaves the sentiment untouched and reports when OpenAI errors' do
    allow(Sentry).to receive(:capture_exception)
    stub_openai(status: 500, body: { error: { message: 'boom' } })

    described_class.new.tag([entry.id])

    expect(entry.reload.sentiment).to eq([])
    expect(Sentry).to have_received(:capture_exception)
  end

  it 'leaves the sentiment untouched and reports when the model refuses' do
    stub_openai(body: { output: [{ type: 'message', content: [{ type: 'refusal', refusal: 'no' }] }] })

    described_class.new.tag([entry.id])

    expect(entry.reload.sentiment).to eq([])
    expect(Sentry).to have_received(:capture_message).with('OpenAI Tagging Error', anything)
  end
end
