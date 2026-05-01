class ToolRun < ApplicationRecord
  belongs_to :user, optional: true

  STATUSES = %w[succeeded failed].freeze

  validates :tool_key, :operation, :status, :occurred_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(occurred_at: :desc) }
  scope :since, ->(time) { where(occurred_at: time..) }
  scope :succeeded, -> { where(status: "succeeded") }
  scope :failed, -> { where(status: "failed") }

  def operation_label
    operation.to_s.tr("-", " ").upcase
  end
end
