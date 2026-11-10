# An image a user's emailed entries should never save, usually a signature
# logo. Admins manage these on the user's admin page; EmailProcessor and
# ImageCollageJob skip any attachment or inline image that matches.
class IgnoredEmailImage < ActiveRecord::Base
  KINDS = {
    "image" => "Looks like this image",
    "filename" => "Filename or URL contains"
  }.freeze

  belongs_to :user

  normalizes :pattern, with: ->(pattern) { pattern.strip.downcase.presence }

  validates :kind, inclusion: { in: KINDS.keys }
  validate :value_usable

  def self.matcher_for(user)
    Matcher.new(where(user: user).to_a)
  end

  def image?
    kind == "image"
  end

  def label
    KINDS[kind]
  end

  def value
    image? ? image_url : pattern
  end

  # The admin form has one field: the text a filename rule looks for,
  # or for an image rule, the URL of a sample to fingerprint. Set kind first.
  def value=(value)
    value = value.to_s.strip
    if image?
      self.image_url = value
      sample = ImageFingerprint.from_url(value) if value.present?
      self.fingerprint = sample&.pixels
      self.aspect_ratio = sample&.aspect_ratio
      @image_fingerprint = nil
    else
      self.pattern = value
    end
  end

  def image_fingerprint
    return if fingerprint.blank? || aspect_ratio.blank?

    @image_fingerprint ||= ImageFingerprint.new(pixels: fingerprint, aspect_ratio: aspect_ratio)
  end

  # Checks one email's images against all of a user's rules. Image rules need
  # the image itself, so callers pass a block returning its ImageFingerprint;
  # the block only runs when the user has image rules.
  class Matcher
    def initialize(rules)
      @filenames = rules.reject(&:image?).map(&:pattern)
      @images = rules.select(&:image?).filter_map(&:image_fingerprint)
    end

    # name is an attachment's filename or an inline image's URL.
    def ignore?(name: nil)
      name = name.to_s.downcase
      return true if name.present? && @filenames.any? { |pattern| name.include?(pattern) }
      return false if @images.empty? || !block_given?

      fingerprint = yield
      !fingerprint.nil? && @images.any? { |image| image.matches?(fingerprint) }
    end
  end

  private

  def value_usable
    if !image?
      errors.add(:base, "Enter the filename to match.") if pattern.blank?
    elsif image_url.blank?
      errors.add(:base, "Paste the link to the image.")
    elsif image_fingerprint.nil?
      errors.add(:base, "That link couldn't be loaded as an image.")
    elsif !image_fingerprint.detailed?
      errors.add(:base, "That image is too plain to recognize reliably. Use a filename rule instead.")
    end
  end
end
