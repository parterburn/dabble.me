require 'rails_helper'

RSpec.describe ImageFingerprint do
  let(:logo) { signature_logo }
  let(:logo_print) { described_class.from_bytes(jpeg_bytes(logo)) }

  it "matches the copy of an image we stored after it was re-saved" do
    stored = described_class.from_bytes(stored_copy(jpeg_bytes(logo)))

    expect(logo_print.correlation(stored)).to be > 0.99
    expect(logo_print.matches?(stored)).to be(true)
  end

  it "matches a resized copy and the PNG original" do
    smaller = described_class.from_bytes(jpeg_bytes(logo.resize(0.5), quality: 70))
    png = described_class.from_bytes(logo.pngsave_buffer)

    expect(logo_print.matches?(smaller)).to be(true)
    expect(logo_print.matches?(png)).to be(true)
  end

  it "reads an image from a file path" do
    file = Tempfile.new(["logo", ".jpg"])
    file.binmode
    file.write(jpeg_bytes(logo))
    file.flush

    expect(described_class.from_file(file.path).matches?(logo_print)).to be(true)
  ensure
    file&.close!
  end

  it "does not match a different logo of the same shape" do
    other = described_class.from_bytes(jpeg_bytes(signature_logo(variant: 1)))

    expect(logo_print.matches?(other)).to be(false)
  end

  it "does not match photos" do
    photos = (1..5).map { |seed| described_class.from_bytes(jpeg_bytes(photo_like(seed))) }

    expect(photos.none? { |photo| logo_print.matches?(photo) }).to be(true)
  end

  it "does not match the same image stretched to another shape" do
    stretched = described_class.from_bytes(jpeg_bytes(logo.resize(1, vscale: 1.5)))

    expect(logo_print.correlation(stretched)).to be > 0.97
    expect(logo_print.matches?(stretched)).to be(false)
  end

  it "flags a near-blank image as too plain to use" do
    expect(logo_print.detailed?).to be(true)
    expect(described_class.from_bytes(jpeg_bytes(blank_image)).detailed?).to be(false)
  end

  it "returns nil for bytes that aren't an image" do
    expect(described_class.from_bytes("not an image")).to be_nil
    expect(described_class.from_bytes(nil)).to be_nil
  end

  it "fetches from a URL through the collage downloader" do
    allow(CollageGenerator).to receive(:fetch).with("https://example.com/logo.jpg").and_return(jpeg_bytes(logo))

    expect(described_class.from_url("https://example.com/logo.jpg").matches?(logo_print)).to be(true)
  end
end
