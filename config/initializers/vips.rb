# frozen_string_literal: true

# Dabble Me processes untrusted user images with libvips (CarrierWave::Vips,
# CollageGenerator, ImageProcessing::Vips). libvips marks some loaders/savers as
# "untrusted" / unfuzzed (Magick, SVG, PDF, JPEG 2000, JXL, etc.). Keep those
# disabled process-wide so crafted uploads cannot exercise them.
#
# Supported formats (JPEG, PNG, GIF, WebP, HEIC/HEIF) use trusted loaders and
# remain available. Requires libvips >= 8.13 and ruby-vips >= 2.2.1.
#
# Related: CVE-2026-66066 / GHSA-xr9x-r78c-5hrm (Active Storage path; Dabble Me
# does not use Active Storage variants, but shares the same libvips surface).

begin
  require 'nokogiri'
rescue LoadError
  # Ensure nokogiri is loaded before vips, which also depends on libxml2.
  # See https://github.com/sparklemotion/nokogiri/discussions/2746
end

require 'ruby-vips'

unless Vips.respond_to?(:block_untrusted)
  raise <<~ERROR.squish
    libvips untrusted operations cannot be disabled. Blocking them requires
    libvips 8.13+ and ruby-vips 2.2.1+. Upgrade libvips/ruby-vips before
    processing untrusted image uploads.
  ERROR
end

Vips.block_untrusted(true)
