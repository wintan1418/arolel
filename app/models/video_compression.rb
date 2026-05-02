require "fileutils"

class VideoCompression < ApplicationRecord
  belongs_to :user

  STATUSES = %w[queued processing succeeded failed].freeze
  INPUT_EXTENSIONS = %w[.mp4 .m4v .mov .webm].freeze
  MAX_BYTES = ENV.fetch("VIDEO_COMPRESSION_MAX_MB", 200).to_i.megabytes
  MAX_QUEUE = ENV.fetch("VIDEO_COMPRESSION_MAX_QUEUE", 2).to_i
  OUTPUT_TTL = ENV.fetch("VIDEO_COMPRESSION_TTL_HOURS", 24).to_i.hours

  validates :status, inclusion: { in: STATUSES }
  validates :original_filename, :input_path, :input_bytes, presence: true

  scope :active, -> { where(status: %w[queued processing]) }
  scope :recent, -> { order(created_at: :desc) }

  def self.accepted_extension?(filename)
    INPUT_EXTENSIONS.include?(File.extname(filename.to_s).downcase)
  end

  def self.purge_expired!
    where(expires_at: ...Time.current).find_each do |video_compression|
      video_compression.purge_files!
      video_compression.destroy!
    end
  end

  def active?
    status.in?(%w[queued processing])
  end

  def succeeded?
    status == "succeeded"
  end

  def failed?
    status == "failed"
  end

  def expired?
    expires_at.present? && expires_at.past?
  end

  def output_available?
    succeeded? && !expired? && output_path.present? && File.exist?(output_path)
  end

  def output_name
    output_filename.presence || "#{base_name}-compressed.mp4"
  end

  def purge_files!
    safe_rm_f(input_path)
    safe_rm_f(output_path)
    parent = File.dirname(input_path.to_s)
    FileUtils.rm_rf(parent) if safe_storage_path?(parent)
  end

  def base_name
    File.basename(original_filename, ".*").parameterize.presence || "video"
  end

  private

  def safe_rm_f(path)
    FileUtils.rm_f(path) if safe_storage_path?(path)
  end

  def safe_storage_path?(path)
    clean_path = Pathname.new(path.to_s).cleanpath.to_s
    root = Rails.root.join("storage", "video_compressions").cleanpath.to_s
    clean_path.start_with?("#{root}/")
  end
end
