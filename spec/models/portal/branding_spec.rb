require 'rails_helper'

# B02a: the colours of a firm are refused when text cannot be read on them (WCAG AA: 4.5 to 1), the logo is a small PNG or JPEG.
RSpec.describe Portal::Branding do
  let(:entity) { create(:entity) }
  let(:png) { "\x89PNG\r\n\x1A\n".b + ('x' * 100) }

  def branding(**attrs) = described_class.new(entity_id: entity.id, display_name: 'Fiduciaire Martin', **attrs)

  describe Portal::Contrast do
    it 'follows the WCAG definition: black on white is 21 to 1, a colour on itself 1 to 1' do
      expect(described_class.ratio('#000000', '#ffffff')).to be_within(0.01).of(21.0)
      expect(described_class.ratio('#336699', '#336699')).to be_within(0.001).of(1.0)
    end

    it 'gives the known ratio of a mid grey on white (4.54 to 1 for #767676)' do
      expect(described_class.ratio('#767676', '#ffffff')).to be_within(0.01).of(4.54)
    end
  end

  it 'accepts colours that read well' do
    expect(branding(primary_color: '#1f2937', background_color: '#ffffff')).to be_valid
  end

  it 'refuses a button colour that white text cannot be read on' do
    brand = branding(primary_color: '#ffeb3b')
    expect(brand).not_to be_valid
    expect(brand.errors[:primary_color].join).to match(/contrast/i)
  end

  it 'refuses a background that the dark text cannot be read on' do
    expect(branding(background_color: '#374151')).not_to be_valid
  end

  it 'refuses anything that is not a six-digit hexadecimal colour' do
    expect(branding(primary_color: 'red')).not_to be_valid
    expect(branding(primary_color: 'url(javascript:alert(1))')).not_to be_valid
    expect(branding(background_color: '#fff; color: red')).not_to be_valid
  end

  it 'takes a PNG or a JPEG logo of 200 KB at most' do
    expect(branding(logo: png, logo_content_type: 'image/png')).to be_valid
    expect(branding(logo: png + ('x' * 210_000), logo_content_type: 'image/png')).not_to be_valid
  end

  it 'refuses an SVG, and a file that is not what it says' do
    expect(branding(logo: '<svg onload="x()"/>', logo_content_type: 'image/svg+xml')).not_to be_valid
    expect(branding(logo: '<html>', logo_content_type: 'image/png')).not_to be_valid
  end

  it 'has a display name, short' do
    expect(branding(display_name: '')).not_to be_valid
    expect(branding(display_name: 'x' * 61)).not_to be_valid
  end
end
