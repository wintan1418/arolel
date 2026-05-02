require "fileutils"

class VideoCompression < ApplicationRecord
  belongs_to :user

  OPERATIONS = {
    "mp4-to-mp3" => {
      label: "MP4 to MP3",
      input_extensions: %w[.mp4 .m4a .mov],
      output_extension: "mp3",
      output_content_type: "audio/mpeg",
      output_suffix: "audio"
    },
    "webm-to-mp4" => {
      label: "WebM to MP4",
      input_extensions: %w[.webm],
      output_extension: "mp4",
      output_content_type: "video/mp4",
      output_suffix: "converted"
    },
    "compress-video" => {
      label: "Video compression",
      input_extensions: %w[.mp4 .m4v .mov .webm],
      output_extension: "mp4",
      output_content_type: "video/mp4",
      output_suffix: "compressed"
    }
  }.freeze

  STATUSES = %w[queued processing succeeded failed].freeze
  INPUT_EXTENSIONS = OPERATIONS.values.flat_map { |config| config[:input_extensions] }.uniq.freeze
  MAX_BYTES = ENV.fetch("MEDIA_CONVERSION_MAX_MB", ENV.fetch("VIDEO_COMPRESSION_MAX_MB", 200)).to_i.megabytes
  MAX_QUEUE = ENV.fetch("VIDEO_COMPRESSION_MAX_QUEUE", 2).to_i
  OUTPUT_TTL = ENV.fetch("VIDEO_COMPRESSION_TTL_HOURS", 24).to_i.hours

  validates :status, inclusion: { in: STATUSES }
  validates :operation, inclusion: { in: OPERATIONS.keys }
  validates :original_filename, :input_path, :input_bytes, presence: true
  validates :progress_percent, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :active, -> { where(status: %w[queued processing]) }
  scope :recent, -> { order(created_at: :desc) }

  def self.accepted_extension?(filename, operation)
    config_for(operation)[:input_extensions].include?(File.extname(filename.to_s).downcase)
  end

  def self.config_for(operation)
    OPERATIONS.fetch(operation)
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
    output_filename.presence || "#{base_name}-#{operation_config[:output_suffix]}.#{output_extension}"
  end

  def output_extension
    operation_config[:output_extension]
  end

  def output_content_type
    operation_config[:output_content_type]
  end

  def operation_label
    operation_config[:label]
  end

  def output_basename
    "output.#{output_extension}"
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

  def operation_config
    self.class.config_for(operation)
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
