class Contract < ApplicationRecord
  belongs_to :user

  TEMPLATES = %w[service nda consulting].freeze

  before_validation :assign_slug, on: :create
  before_validation :assign_title, on: :create

  validates :slug, presence: true, uniqueness: true
  validates :title, presence: true
  validates :template, inclusion: { in: TEMPLATES }
  validate :png_data_url

  scope :recent, -> { order(created_at: :desc) }

  def self.suggest_title(user)
    count = user ? user.contracts.count : 0
    "Contract #{1001 + count}"
  end

  private

  def assign_slug
    return if slug.present?

    loop do
      candidate = SecureRandom.alphanumeric(7).downcase
      break self.slug = candidate unless self.class.exists?(slug: candidate)
    end
  end

  def assign_title
    self.title ||= self.class.suggest_title(user)
  end

  def png_data_url
    return if signer_image_data.blank?
    return if signer_image_data.to_s.start_with?("data:image/png;base64,")

    errors.add(:signer_image_data, "must be a PNG data URL")
  end
end
