require "fileutils"

class VideoCompressionsController < ApplicationController
  rate_limit to: 3, within: 1.hour, only: :create,
             with: -> { redirect_to media_path(op: params[:operation].presence || "compress-video"), alert: "Too many media uploads. Please try again later." }

  rescue_from ActiveRecord::RecordNotFound, with: :handle_missing_conversion

  before_action :set_video_compression, only: %i[show download]

  def create
    VideoCompression.purge_expired!
    operation = safe_operation(params[:operation].presence || "compress-video")
    upload = params[:file]
    validate_upload!(upload, operation)
    enforce_queue_limits!

    video_compression = create_video_compression!(upload, operation)
    job = CompressVideoJob.perform_later(video_compression.id)
    video_compression.update!(active_job_id: job.job_id)

    redirect_to video_compression_path(video_compression), notice: "#{video_compression.operation_label} queued. You can keep this page open and refresh for status.", status: :see_other
  rescue ArgumentError => e
    redirect_to media_path(op: params[:operation].presence || "compress-video"), alert: e.message, status: :see_other
  end

  def show
    if @video_compression.expired?
      operation = @video_compression.operation
      @video_compression.purge_files!
      @video_compression.destroy!
      redirect_to media_path(op: operation), alert: "That converted file has expired.", status: :see_other
      return
    end

    page_title "#{@video_compression.operation_label} · Arolel"
  end

  def download
    unless @video_compression.output_available?
      redirect_to video_compression_path(@video_compression), alert: "Converted file is not available yet.", status: :see_other
      return
    end

    video_compression = @video_compression
    output_path = safe_output_path(video_compression)
    response.headers["Content-Type"] = video_compression.output_content_type
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: video_compression.output_name)
    response.headers["Content-Length"] = File.size(output_path).to_s
    self.status = :ok
    self.response_body = streamed_file_body(output_path, video_compression)
  end

  private

  def set_video_compression
    @video_compression = current_user.video_compressions.find(params[:id])
  end

  def validate_upload!(upload, operation)
    raise ArgumentError, "Choose a file to convert." if upload.blank?
    raise ArgumentError, "Upload a supported file for #{VideoCompression.config_for(operation)[:label]}." unless VideoCompression.accepted_extension?(upload.original_filename, operation)

    if upload.size.to_i > VideoCompression::MAX_BYTES
      raise ArgumentError, "Keep media conversion files under #{VideoCompression::MAX_BYTES / 1.megabyte}MB for now."
    end
  end

  def enforce_queue_limits!
    if current_user.video_compressions.active.exists?
      raise ArgumentError, "You already have a media conversion queued or processing. Wait for it to finish before starting another."
    end

    if VideoCompression.active.count >= VideoCompression::MAX_QUEUE
      raise ArgumentError, "The media conversion queue is full. Please try again later."
    end
  end

  def create_video_compression!(upload, operation)
    video_compression = current_user.video_compressions.create!(
      operation: operation,
      status: "queued",
      progress_percent: 0,
      status_message: "Queued",
      original_filename: upload.original_filename,
      content_type: upload.content_type,
      input_bytes: upload.size,
      input_path: placeholder_input_path(upload.original_filename, operation)
    )

    input_path = input_path_for(video_compression.id, upload)
    FileUtils.mkdir_p(File.dirname(input_path))
    FileUtils.copy_stream(upload.tempfile, input_path)
    video_compression.update!(input_path: input_path)
    video_compression
  rescue StandardError
    video_compression&.destroy
    FileUtils.rm_f(input_path) if defined?(input_path)
    raise
  end

  def input_path_for(video_compression_id, upload)
    Rails.root.join("storage", "video_compressions", video_compression_id.to_i.to_s, "input#{safe_extension(upload.original_filename)}").to_s
  end

  def placeholder_input_path(filename, operation)
    extension = File.extname(filename).downcase
    Rails.root.join("storage", "video_compressions", "pending", operation, "input#{extension}").to_s
  end

  def safe_output_path(video_compression)
    path = Rails.root.join("storage", "video_compressions", video_compression.id.to_i.to_s, video_compression.output_basename)
    root = Rails.root.join("storage", "video_compressions").to_s
    raise ActionController::RoutingError, "Not Found" unless path.to_s.start_with?(root)

    path.to_s
  end

  def safe_extension(filename)
    extension = File.extname(filename).downcase
    VideoCompression::INPUT_EXTENSIONS.include?(extension) ? extension : ".mp4"
  end

  def safe_operation(operation)
    raise ArgumentError, "Unknown media conversion." unless VideoCompression::OPERATIONS.key?(operation)

    operation
  end

  def cleanup_downloaded_conversion(video_compression)
    video_compression.reload
    video_compression.purge_files!
    video_compression.update_columns(
      output_path: nil,
      output_bytes: nil,
      status_message: "Downloaded and removed from server",
      expires_at: 10.minutes.from_now,
      updated_at: Time.current
    )
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def streamed_file_body(path, video_compression)
    Enumerator.new do |yielder|
      File.open(path, "rb") do |file|
        while (chunk = file.read(64.kilobytes))
          yielder << chunk
        end
      end
    ensure
      cleanup_downloaded_conversion(video_compression)
    end
  end

  def handle_missing_conversion
    redirect_to media_path(op: params[:operation].presence || "mp4-to-mp3"), alert: "That conversion is no longer available.", status: :see_other
  end
end
