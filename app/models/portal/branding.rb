# The look of the portal in the name of the firm. Anything that could carry code is refused: colours are six hexadecimal digits, the logo a PNG or JPEG whose first bytes say so.
class Portal::Branding < ApplicationRecord
  TEXT_COLOR = "#111827".freeze # the colour of the text on the background
  BUTTON_TEXT = "#ffffff".freeze # the text on the primary colour
  MAX_LOGO_BYTES = 200.kilobytes
  LOGO_TYPES = { "image/png" => "\x89PNG\r\n\x1A\n".b, "image/jpeg" => "\xFF\xD8\xFF".b }.freeze
  HEX = /\A#[0-9a-fA-F]{6}\z/

  belongs_to :company, class_name: "Portal::Company", foreign_key: :entity_id, inverse_of: false
  belongs_to :updated_by, class_name: "User", optional: true

  validates :display_name, presence: true, length: { maximum: 60 }
  validates :sender_name, length: { maximum: 60 }, allow_blank: true
  validates :primary_color, :background_color, format: { with: HEX, message: "must be a colour like #1f2937" }
  validate :colours_are_readable
  validate :logo_is_safe

  def logo? = logo.present?

  private

  def colours_are_readable
    errors.add(:primary_color, "contrast with white text is below the 4.5 to 1 of WCAG AA") if primary_color =~ HEX && Portal::Contrast.ratio(primary_color, BUTTON_TEXT) < Portal::Contrast::AA
    errors.add(:background_color, "contrast with the text is below the 4.5 to 1 of WCAG AA") if background_color =~ HEX && Portal::Contrast.ratio(background_color, TEXT_COLOR) < Portal::Contrast::AA
  end

  def logo_is_safe
    return if logo.blank?

    magic = LOGO_TYPES[logo_content_type]
    errors.add(:logo, "must be a PNG or a JPEG") unless magic && logo.b.start_with?(magic)
    errors.add(:logo, "must be #{MAX_LOGO_BYTES / 1.kilobyte} KB or less") if logo.bytesize > MAX_LOGO_BYTES
  end
end
