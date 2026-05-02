require "fileutils"

class VideoCompressionsController < ApplicationController
  rate_limit to: 3, within: 1.hour, only: :create,
             with: -> { redirect_to media_path(op: "compress-video"), alert: "Too many heavy video uploads. Please try again later." }

  before_action :set_video_compression, only: %i[show download]

  def create
    VideoCompression.purge_expired!
    upload = params[:file]
    validate_upload!(upload)
    enforce_queue_limits!

    video_compression = create_video_compression!(upload)
    job = CompressVideoJob.perform_later(video_compression.id)
    video_compression.update!(active_job_id: job.job_id)

    redirect_to video_compression_path(video_compression), notice: "Video compression queued. You can keep this page open and refresh for status.", status: :see_other
  rescue ArgumentError => e
    redirect_to media_path(op: "compress-video"), alert: e.message, status: :see_other
  end

  def show
    if @video_compression.expired?
      @video_compression.purge_files!
      @video_compression.destroy!
      redirect_to media_path(op: "compress-video"), alert: "That compressed video has expired.", status: :see_other
      return
    end

    page_title "Video compression · Arolel"
  end

  def download
    unless @video_compression.output_available?
      redirect_to video_compression_path(@video_compression), alert: "Compressed video is not available yet.", status: :see_other
      return
    end

    send_file safe_output_path(@video_compression.id),
              filename: @video_compression.output_name,
              type: "video/mp4",
              disposition: "attachment"
  end

  private

  def set_video_compression
    @video_compression = current_user.video_compressions.find(params[:id])
  end

  def validate_upload!(upload)
    raise ArgumentError, "Choose a video to compress." if upload.blank?
    raise ArgumentError, "Upload an MP4, MOV, M4V or WebM video." unless VideoCompression.accepted_extension?(upload.original_filename)

    if upload.size.to_i > VideoCompression::MAX_BYTES
      raise ArgumentError, "Keep heavy video compression under #{VideoCompression::MAX_BYTES / 1.megabyte}MB for now."
    end
  end

  def enforce_queue_limits!
    if current_user.video_compressions.active.exists?
      raise ArgumentError, "You already have a video compression queued or processing. Wait for it to finish before starting another."
    end

    if VideoCompression.active.count >= VideoCompression::MAX_QUEUE
      raise ArgumentError, "The video compression queue is full. Please try again later."
    end
  end

  def create_video_compression!(upload)
    video_compression = current_user.video_compressions.create!(
      status: "queued",
      original_filename: upload.original_filename,
      content_type: upload.content_type,
      input_bytes: upload.size,
      input_path: placeholder_input_path(upload.original_filename)
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

  def placeholder_input_path(filename)
    extension = File.extname(filename).downcase
    Rails.root.join("storage", "video_compressions", "pending", "input#{extension}").to_s
  end

  def safe_output_path(video_compression_id)
    path = Rails.root.join("storage", "video_compressions", video_compression_id.to_i.to_s, "output.mp4")
    root = Rails.root.join("storage", "video_compressions").to_s
    raise ActionController::RoutingError, "Not Found" unless path.to_s.start_with?(root)

    path.to_s
  end

  def safe_extension(filename)
    extension = File.extname(filename).downcase
    VideoCompression::INPUT_EXTENSIONS.include?(extension) ? extension : ".mp4"
  end
end
