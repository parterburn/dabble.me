require "rails_helper"
load Rails.root.join("script/cleanup_ai_conversations.rb")

RSpec.describe AiConversationCleanup do
  let(:ai_reply) { "<div data-content='dabblemegpt'><strong>🤖 DabbleMeGPT:</strong><br/><p>What a day. <strong>What stood out?</strong></p></div>" }

  describe ".clean" do
    it "drops the AI reply and your replies after it" do
      body = "<p>Original entry.</p><hr>#{ai_reply}<hr><strong>👤 You:</strong><br/><p>My reply.</p><hr>#{ai_reply}"
      expect(described_class.clean(body)).to eq("<p>Original entry.</p>")
    end

    it "keeps your replies, without the label, when asked" do
      body = "<p>Original entry.</p><hr>#{ai_reply}<hr><strong>👤 You:</strong><br/><p>My reply.</p>"
      expect(described_class.clean(body, keep_replies: true)).to eq("<p>Original entry.</p><hr><p>My reply.</p>")
    end

    it "keeps an emailed entry that came before the AI reply, without its label" do
      body = "<p>Morning.</p><hr><strong>👤 You:</strong><br/>Evening email.<hr>#{ai_reply}"
      expect(described_class.clean(body)).to eq("<p>Morning.</p><hr>Evening email.")
    end

    it "keeps entries added after the conversation" do
      body = "<p>Original.</p><hr>#{ai_reply}<hr><p>Emailed later that day.</p>"
      expect(described_class.clean(body)).to eq("<p>Original.</p><hr><p>Emailed later that day.</p>")
    end

    it "handles replies saved through the web editor, which relabels them AI Assistant" do
      body = %(<p>Original.</p><hr/><div><b>🤖 AI Assistant:</b><br><p>Reply.</p></div>)
      expect(described_class.clean(body)).to eq("<p>Original.</p>")
    end

    it "leaves someone who just wrote the word DabbleMeGPT alone" do
      body = "<p>Tried DabbleMeGPT today. 🤖 Fun!</p>"
      expect(described_class.clean(body)).to eq(body)
    end

    it "returns blank when only AI content is left" do
      expect(described_class.clean(ai_reply)).to be_blank
    end
  end

  describe ".apply! and .restore!" do
    let(:user) { FactoryBot.create(:user) }
    let(:other) { FactoryBot.create(:user) }
    let!(:conversation) { FactoryBot.create(:entry, user: user, body: "<p>Mine.</p><hr>#{ai_reply}") }
    let!(:only_ai) { FactoryBot.create(:entry, user: user, date: 3.days.ago, body: ai_reply) }
    let!(:others) { FactoryBot.create(:entry, user: other, body: "<p>Theirs.</p><hr>#{ai_reply}") }
    let!(:plain) { FactoryBot.create(:entry, user: user, date: 5.days.ago, body: "<p>No AI here 🤖</p>") }

    before { allow($stdout).to receive(:puts) }

    it "reports counts per user" do
      expect(described_class.report).to eq(user.id => 2, other.id => 1)
    end

    it "cleans only the given users, skips entries that would be empty, and can restore" do
      backup = described_class.apply!(user_ids: [user.id])

      expect(conversation.reload.body).to eq("<p>Mine.</p>")
      expect(only_ai.reload.body).to eq(ai_reply)
      expect(others.reload.body).to include("dabblemegpt")
      expect(plain.reload.body).to eq("<p>No AI here 🤖</p>")

      described_class.restore!(backup)
      expect(conversation.reload.body).to eq("<p>Mine.</p><hr>#{ai_reply}")
    ensure
      File.delete(backup) if backup && File.exist?(backup)
    end
  end
end
