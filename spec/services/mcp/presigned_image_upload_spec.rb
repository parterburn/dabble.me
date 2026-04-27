# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::PresignedImageUpload do
  include_context "has all objects"

  describe "#call" do
    it "returns a scoped presigned PUT upload target" do
      result = described_class.new(user: paid_user).call(
        filename: "journal-photo.jpg",
        content_type: "image/jpeg"
      )

      expect(result[:success]).to eq(true)
      expect(result[:upload_method]).to eq("PUT")
      expect(result[:upload_url]).to include("X-Amz-Signature")
      expect(result[:uploaded_image_key]).to start_with(described_class.key_prefix_for(paid_user))
      expect(result[:uploaded_image_key]).to end_with(".jpg")
      expect(result[:upload_headers]).to include(
        "Content-Type" => "image/jpeg",
        "x-amz-acl" => "public-read"
      )
      expect(Time.iso8601(result[:expires_at])).to be_between(14.minutes.from_now, 16.minutes.from_now)
    end

    it "rejects unsupported content types" do
      result = described_class.new(user: paid_user).call(
        filename: "notes.txt",
        content_type: "text/plain"
      )

      expect(result[:success]).to eq(false)
      expect(result[:errors].first).to include("not an allowed image type")
    end
  end

  describe ".key_allowed_for_user?" do
    it "allows only the user's temporary MCP upload prefix" do
      allowed = described_class.build_key(user: paid_user, filename: "photo.png", content_type: "image/png")
      other_user_key = allowed.sub(paid_user.user_key, free_ai.user_key)

      expect(described_class.key_allowed_for_user?(paid_user, allowed)).to eq(true)
      expect(described_class.key_allowed_for_user?(paid_user, other_user_key)).to eq(false)
      expect(described_class.key_allowed_for_user?(paid_user, "#{described_class.key_prefix_for(paid_user)}../photo.png")).to eq(false)
    end
  end
end
