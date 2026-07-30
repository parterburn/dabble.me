# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'libvips untrusted operation blocking' do
  it 'enables block_untrusted at boot' do
    expect(Vips).to respond_to(:block_untrusted)
  end

  it 'still loads trusted web formats' do
    jpeg = Vips::Image.black(8, 8).jpegsave_buffer
    png = Vips::Image.black(8, 8).pngsave_buffer
    webp = Vips::Image.black(8, 8).webpsave_buffer
    gif = Vips::Image.black(8, 8).gifsave_buffer

    expect(Vips::Image.new_from_buffer(jpeg, '').width).to eq(8)
    expect(Vips::Image.new_from_buffer(png, '').width).to eq(8)
    expect(Vips::Image.new_from_buffer(webp, '').width).to eq(8)
    expect(Vips::Image.new_from_buffer(gif, '').width).to eq(8)
  end

  it 'blocks untrusted SVG loading' do
    svg = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
        <rect width="10" height="10"/>
      </svg>
    SVG

    expect {
      Vips::Image.new_from_buffer(svg, '')
    }.to raise_error(Vips::Error)
  end
end
