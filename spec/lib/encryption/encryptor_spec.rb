require 'rails_helper'

RSpec.describe Encryption::Encryptor do
  let(:user) { FactoryBot.create(:user) }

  it 'writes ciphertext, including posting keys that are looked up by value' do
    entry = FactoryBot.create(:entry, user: user, body: '<p>now encrypted</p>')

    expect(ciphertext?(stored_value(entry, 'body'))).to be(true)
    expect(ciphertext?(stored_value(user, 'user_key'))).to be(true)
    expect(ciphertext?(stored_value(user, 'image_key'))).to be(true)
    expect(User.find_by(user_key: user.user_key)).to eq(user)
    expect(User.find_by(image_key: user.image_key)).to eq(user)
  end

  it 'writes plaintext only inside forcing(:plaintext)' do
    entry = FactoryBot.create(:entry, user: user, body: '<p>secret</p>')

    described_class.forcing(:plaintext) do
      entry.update!(body: '<p>back to plain</p>')
    end
    expect(stored_value(entry, 'body')).to eq('<p>back to plain</p>')
    expect(Entry.find(entry.id).body).to eq('<p>back to plain</p>')

    entry.update!(body: '<p>encrypted again</p>')
    expect(ciphertext?(stored_value(entry, 'body'))).to be(true)
    expect(Entry.find(entry.id).body).to eq('<p>encrypted again</p>')
  end
end
