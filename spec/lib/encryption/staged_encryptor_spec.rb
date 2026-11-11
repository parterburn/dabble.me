require 'rails_helper'

RSpec.describe Encryption::StagedEncryptor do
  let(:user) { FactoryBot.create(:user) }

  context 'before ciphertext writes are turned on' do
    around { |example| with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => 'false') { example.run } }

    it 'writes plaintext, as the app did before encryption' do
      entry = FactoryBot.create(:entry, user: user, body: '<p>still plain</p>')
      expect(stored_value(entry, 'body')).to eq('<p>still plain</p>')
      expect(stored_value(user, 'user_key')).to eq(user.user_key)
      expect(User.find_by(user_key: user.user_key)).to eq(user)
    end

    it 'still reads rows another process already encrypted' do
      entry = with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => 'true') do
        FactoryBot.create(:entry, user: user, body: '<p>written encrypted</p>')
      end
      expect(ciphertext?(stored_value(entry, 'body'))).to be(true)
      expect(Entry.find(entry.id).body).to eq('<p>written encrypted</p>')
    end

    it 'finds a user whose keys another process already encrypted' do
      encrypted = with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => 'true') { FactoryBot.create(:user) }
      expect(ciphertext?(stored_value(encrypted, 'user_key'))).to be(true)
      expect(User.find_by(user_key: encrypted.user_key)).to eq(encrypted)
    end
  end

  it 'writes ciphertext once turned on' do
    with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => 'true') do
      entry = FactoryBot.create(:entry, user: user, body: '<p>now encrypted</p>')
      expect(ciphertext?(stored_value(entry, 'body'))).to be(true)
    end
  end

  it 'is off by default in production and on elsewhere' do
    with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => nil) do
      expect(described_class.write_ciphertext?).to be(true)
      allow(Rails.env).to receive(:production?).and_return(true)
      expect(described_class.write_ciphertext?).to be(false)
    end
  end
end

# Posting and photo keys are looked up by value, so each stage has to find
# keys written by the stage before and the stage after.
RSpec.describe 'Posting key lookups across the staged rollout' do
  def user_written_with(write)
    with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => write) { FactoryBot.create(:user) }
  end

  %w[false true].each do |reader|
    %w[false true].each do |writer|
      it "finds keys written with WRITE=#{writer} from a process with WRITE=#{reader}" do
        user = user_written_with(writer)
        expect(ciphertext?(stored_value(user, 'user_key'))).to be(writer == 'true')
        expect(ciphertext?(stored_value(user, 'image_key'))).to be(writer == 'true')

        with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => reader) do
          found = User.find_by(user_key: user.user_key)
          expect(found).to eq(user)
          expect(found.user_key).to eq(user.user_key)
          expect(User.find_by(image_key: user.image_key)).to eq(user)
          expect(User.where(user_key: user.user_key).or(User.where(image_key: user.user_key))).to exist
          expect(FactoryBot.build(:user, user_key: user.user_key)).not_to be_valid
          expect(FactoryBot.build(:user, image_key: user.image_key)).not_to be_valid
        end
      end
    end
  end

  it 'rotates a posting key in either stage' do
    %w[false true].each do |write|
      with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => write) do
        user = FactoryBot.create(:user)
        old_key = user.user_key
        user.rotate_user_key!
        expect(User.find_by(user_key: old_key)).to be_nil
        expect(User.find_by(user_key: user.user_key)).to eq(user)
      end
    end
  end
end
