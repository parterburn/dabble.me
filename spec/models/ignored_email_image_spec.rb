require 'rails_helper'

RSpec.describe IgnoredEmailImage do
  include_context 'has all objects'

  let(:logo_url) { "https://d10r8m94hrfowu.cloudfront.net/#{paid_user.image_key}/2026-09-20/logo.jpg" }

  def build_rule(kind, value, owner: paid_user)
    described_class.new(user: owner, kind: kind).tap { |rule| rule.value = value }
  end

  describe "validation" do
    it "keeps a filename rule's text, lowercased" do
      rule = build_rule("filename", "  Image001.JPG ")

      expect(rule).to be_valid
      expect(rule.pattern).to eq("image001.jpg")
      expect(build_rule("filename", " ")).not_to be_valid
    end

    it "fingerprints the linked image for an image rule" do
      allow(CollageGenerator).to receive(:fetch).with(logo_url).and_return(stored_copy(jpeg_bytes(signature_logo)))
      rule = build_rule("image", logo_url)

      expect(rule).to be_valid
      expect(rule.image_url).to eq(logo_url)
      expect(rule.fingerprint.bytesize).to eq(ImageFingerprint::GRID**2)
      expect(rule.aspect_ratio).to be_within(0.05).of(300.0 / 86)

      rule.save!
      expect(rule.reload.image_fingerprint.matches?(ImageFingerprint.from_bytes(jpeg_bytes(signature_logo)))).to be(true)
    end

    it "rejects a link that isn't an image" do
      allow(CollageGenerator).to receive(:fetch).and_return(nil)
      rule = build_rule("image", logo_url)

      expect(rule).not_to be_valid
      expect(rule.errors.full_messages).to eq(["That link couldn't be loaded as an image."])
    end

    it "rejects an image too plain to recognize" do
      allow(CollageGenerator).to receive(:fetch).and_return(jpeg_bytes(blank_image))
      rule = build_rule("image", logo_url)

      expect(rule).not_to be_valid
      expect(rule.errors.full_messages.join).to match(/too plain/)
    end

    it "rejects other kinds, including the retired content type rule" do
      expect(build_rule("regex", "x")).not_to be_valid
      expect(build_rule("content_type", "application/octet-stream")).not_to be_valid
    end
  end

  describe ".matcher_for" do
    let(:logo_print) { ImageFingerprint.from_bytes(jpeg_bytes(signature_logo)) }

    before do
      allow(CollageGenerator).to receive(:fetch).and_return(stored_copy(jpeg_bytes(signature_logo)))
      build_rule("filename", "b_logo.png").save!
      build_rule("image", logo_url).save!
      build_rule("filename", "someone-elses.png", owner: user).save!
    end

    let(:matcher) { described_class.matcher_for(paid_user) }

    it "matches filenames and URLs that contain a rule's text, ignoring case" do
      expect(matcher.ignore?(name: "B_LOGO.png")).to be(true)
      expect(matcher.ignore?(name: "https://cdn.example.com/sig/b_logo.png?v=2")).to be(true)
      expect(matcher.ignore?(name: "beach.png")).to be(false)
    end

    it "matches lookalike images through the block" do
      expect(matcher.ignore?(name: "renamed.jpg") { logo_print }).to be(true)
      expect(matcher.ignore?(name: "photo.jpg") { ImageFingerprint.from_bytes(jpeg_bytes(photo_like(1))) }).to be(false)
      expect(matcher.ignore?(name: "unreadable.jpg") { nil }).to be(false)
    end

    it "only uses the user's own rules" do
      expect(matcher.ignore?(name: "someone-elses.png")).to be(false)
      expect(described_class.matcher_for(user).ignore?(name: "b_logo.png")).to be(false)
    end

    it "doesn't load the image when the user has no image rules" do
      expect { |probe| described_class.matcher_for(user).ignore?(name: "photo.jpg", &probe) }.not_to yield_control
    end
  end

  it "is deleted with its user, including DeleteUserJob's user.delete" do
    owner = FactoryBot.create(:user)
    build_rule("filename", "b_logo.png", owner: owner).save!

    expect { owner.delete }.to change(described_class, :count).by(-1)
  end
end
