require 'rails_helper'

RSpec.describe WebauthnCredential, type: :model do
  let(:user) { create(:user) }
  let(:valid_attributes) do
    {
      user: user,
      external_id: SecureRandom.hex(16),
      public_key: SecureRandom.hex(32),
      nickname: "My MacBook",
      sign_count: 0
    }
  end

  it "is valid with valid attributes" do
    expect(WebauthnCredential.new(valid_attributes)).to be_valid
  end

  it "is invalid without a user" do
    valid_attributes[:user] = nil
    expect(WebauthnCredential.new(valid_attributes)).not_to be_valid
  end

  it "is invalid without an external_id" do
    valid_attributes[:external_id] = nil
    expect(WebauthnCredential.new(valid_attributes)).not_to be_valid
  end

  it "is invalid with a non-unique external_id" do
    WebauthnCredential.create!(valid_attributes)
    new_credential = WebauthnCredential.new(valid_attributes)
    expect(new_credential).not_to be_valid
  end

  it "is invalid without a public_key" do
    valid_attributes[:public_key] = nil
    expect(WebauthnCredential.new(valid_attributes)).not_to be_valid
  end

  it "is invalid without a nickname" do
    valid_attributes[:nickname] = nil
    expect(WebauthnCredential.new(valid_attributes)).not_to be_valid
  end

  it "is invalid without a sign_count" do
    valid_attributes[:sign_count] = nil
    expect(WebauthnCredential.new(valid_attributes)).not_to be_valid
  end

  it "is invalid with a negative sign_count" do
    valid_attributes[:sign_count] = -1
    expect(WebauthnCredential.new(valid_attributes)).not_to be_valid
  end

  it "is invalid with a non-integer sign_count" do
    valid_attributes[:sign_count] = 1.5
    expect(WebauthnCredential.new(valid_attributes)).not_to be_valid
  end

  it "belongs to a user" do
    credential = WebauthnCredential.new(valid_attributes)
    expect(credential.user).to eq(user)
  end
end
