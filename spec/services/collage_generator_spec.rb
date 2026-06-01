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

    it "applies EXIF orientation via autorot" do
      gen = described_class.new(urls: [])
      img = Vips::Image.black(100, 200, bands: 3)

      oriented = gen.send(:orient_image, img)

      expect(oriented).to be_a(Vips::Image)
      expect(oriented.width).to eq(100)
      expect(oriented.height).to eq(200)
    end

    it "returns the original image when autorot fails" do
      gen = described_class.new(urls: [])
      img = Vips::Image.black(10, 20, bands: 3)
      allow(img).to receive(:autorot).and_raise(Vips::Error, "autorot failed")

      expect(gen.send(:orient_image, img)).to eq(img)
    end

    it "fits each tile to the cell without cropping (letterbox), exact output size" do
      gen = described_class.new(urls: [])
      # Wide source in a square cell → scaled down, vertical padding.
      img = Vips::Image.black(200, 100, bands: 3).linear(1, [40, 80, 120])
      tile = gen.send(:prepare_tile, img, 100, 100)

      expect(tile.width).to eq(100)
      expect(tile.height).to eq(100)
    end
  end
end
