class FeedbackSubmission < ApplicationRecord
  belongs_to :user, optional: true

  KINDS = %w[suggestion contact].freeze
  STATUSES = %w[new reviewed planned declined shipped].freeze

  validates :kind, :message, :occurred_at, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :recent, -> { order(occurred_at: :desc) }
  scope :suggestions, -> { where(kind: "suggestion") }
  scope :contacts, -> { where(kind: "contact") }
  scope :paid_interest, -> { where(willing_to_pay: true) }

  def sender_label
    name.presence || email.presence || user&.email_address || "guest"
  end
end
