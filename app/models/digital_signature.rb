class DigitalSignature < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, length: { maximum: 80 }
  validates :source_text, length: { maximum: 120 }, allow_blank: true
  validates :style_key, length: { maximum: 40 }, allow_blank: true
  validates :image_data, presence: true, length: { maximum: 750.kilobytes }
  validate :png_data_url

  scope :recent, -> { order(created_at: :desc) }

  private

  def png_data_url
    return if image_data.to_s.start_with?("data:image/png;base64,")

    errors.add(:image_data, "must be a PNG data URL")
  end
end
