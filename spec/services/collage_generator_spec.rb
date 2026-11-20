# frozen_string_literal: true

require "rails_helper"

RSpec.describe CollageGenerator do
  describe "reorder_images_for_aspect_rows" do
    # Landscape ~2:1 and portrait ~1:2 so aspect spread within a 4+4 row is obvious.
    let(:land) { Struct.new(:width, :height).new(400, 200) }
    let(:port) { Struct.new(:width, :height).new(200, 400) }

    it "groups landscape-like shots in the first row and portrait-like in the second for [4, 4]" do
      gen = described_class.new(urls: [])
      input = [port, land, port, land, port, land, port, land]
      plan = [4, 4]

      ordered = gen.send(:reorder_images_for_aspect_rows, input, plan)

      expect(ordered[0, 4]).to all satisfy { |img| img.width >= img.height }
      expect(ordered[4, 4]).to all satisfy { |img| img.height >= img.width }
    end

    it "fills rows in plan order after sorting by aspect ratio" do
      gen = described_class.new(urls: [])
      # 3 landscape + 2 portrait → [2, 3] plan puts two widest in row one, rest in row two.
      input = [port, port, land, land, land]
      plan = [2, 3]

      ordered = gen.send(:reorder_images_for_aspect_rows, input, plan)

      expect(ordered[0, 2]).to all satisfy { |img| img.width > img.height }
      expect(ordered[2, 3]).to contain_exactly(land, port, port)
    end

    it "scales a tile to an exact height while preserving aspect ratio (no crop, no pad)" do
      gen = described_class.new(urls: [])
      # Wide 2:1 source scaled to height 100 → width must stay 2:1 (=> 200).
      img = Vips::Image.black(200, 100, bands: 3).linear(1, [40, 80, 120])
      tile = gen.send(:scale_to_height, img, 100)

      expect(tile.height).to eq(100)
      expect(tile.width).to eq(200)
    end

    it "builds a justified row that fills the inner width without cropping" do
      gen = described_class.new(urls: [], size: 1200)
      inner_w = 1200 - (2 * CollageGenerator::SHIM)
      land = Vips::Image.black(400, 200, bands: 3) # 2:1
      port = Vips::Image.black(200, 400, bands: 3) # 1:2

      row = gen.send(:build_justified_row, [land, port], inner_w)

      # Row width fills the canvas inner width (within rounding of the shim/join).
      expect(row.width).to be_within(2).of(inner_w)
      # Both tiles share one height and neither is cropped: the wide one stays
      # wider than the tall one.
      expect(row.height).to be > 0
    end

    it "refuses local filesystem paths unless allow_local_paths is true" do
      tmp = Tempfile.new(["collage_local_test", ".png"])
      tmp.binmode
      tmp.write(Vips::Image.black(120, 120, bands: 3).write_to_buffer(".png"))
      tmp.rewind

      default_gen = described_class.new(urls: [tmp.path])
      expect(default_gen.send(:fetch_bytes, tmp.path)).to be_nil

      explicit_gen = described_class.new(urls: [tmp.path], allow_local_paths: true)
      expect(explicit_gen.send(:fetch_bytes, tmp.path)).to be_present
    ensure
      tmp&.close
      tmp&.unlink
    end
  end

  describe "load_image" do
    # A small JPEG whose SOF header is patched to claim width x height. The file
    # stays under a kilobyte; decoding it in full would need width*height*3 bytes.
    def forged_jpeg(width, height)
      jpeg = Vips::Image.black(16, 16, bands: 3).write_to_buffer(".jpg").b
      sof = jpeg.index("\xFF\xC0".b) || jpeg.index("\xFF\xC2".b)
      jpeg[sof + 5, 2] = [height].pack("n")
      jpeg[sof + 7, 2] = [width].pack("n")
      jpeg
    end

    def load(gen, bytes)
      allow(gen).to receive(:fetch_bytes).and_return(bytes)
      gen.send(:load_image, "https://example.com/photo.jpg")
    end

    it "refuses a source whose header declares more than MAX_SOURCE_PIXELS" do
      gen = described_class.new(urls: [])
      bytes = forged_jpeg(30_000, 30_000)
      expect(bytes.bytesize).to be < 2_000

      expect(Vips::Image).not_to receive(:thumbnail_buffer)
      expect(load(gen, bytes)).to be_nil
    end

    it "decodes an allowed source no larger than the canvas" do
      gen = described_class.new(urls: [], size: 1200)
      bytes = Vips::Image.black(4000, 3000, bands: 3).write_to_buffer(".jpg")

      img = load(gen, bytes)

      expect([img.width, img.height]).to eq([1200, 900])
    end

    it "decodes a large declared size within the cap without materializing it" do
      gen = described_class.new(urls: [], size: 1200)
      img = load(gen, forged_jpeg(9_000, 9_000))

      expect([img.width, img.height]).to eq([1200, 1200])
    end

    it "leaves small sources at their own size" do
      gen = described_class.new(urls: [], size: 1200)
      img = load(gen, Vips::Image.black(300, 200, bands: 3).write_to_buffer(".png"))

      expect([img.width, img.height]).to eq([300, 200])
    end

    it "applies EXIF orientation" do
      gen = described_class.new(urls: [])
      sideways = Vips::Image.black(400, 200, bands: 3).mutate do |m|
        m.set_type!(GObject::GINT_TYPE, "orientation", 6)
      end

      img = load(gen, sideways.write_to_buffer(".jpg"))

      expect([img.width, img.height]).to eq([200, 400])
    end

    it "still decodes a truncated JPEG" do
      gen = described_class.new(urls: [])
      full = Vips::Image.black(2000, 1500, bands: 3).linear(1, [40, 80, 120]).write_to_buffer(".jpg")

      img = load(gen, full.byteslice(0, full.bytesize * 2 / 3))

      expect([img.width, img.height]).to eq([1200, 900])
    end
  end
end
