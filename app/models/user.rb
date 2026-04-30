class User < ApplicationRecord
  has_secure_password

  has_many :sessions,   dependent: :destroy
  has_many :boards,     dependent: :nullify
  has_many :url_sets,   dependent: :nullify
  has_many :invoices,   dependent: :destroy
  has_many :digital_signatures, dependent: :destroy
  has_many :activity_events, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: { case_sensitive: false },
                             format: { with: URI::MailTo::EMAIL_REGEXP, message: "is not a valid email" }
  validates :password, length: { minimum: 8, maximum: 72 }, if: -> { password.present? }

  def super_admin?
    super_admin || ENV.fetch("SUPER_ADMIN_EMAILS", "").split(",").map(&:strip).include?(email_address)
  end
end
