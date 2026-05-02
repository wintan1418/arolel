require "fileutils"

class CompressVideoJob < ApplicationJob
  queue_as :video

  GLOBAL_LOCK_KEY = 20_260_502

  def perform(video_compression_id)
    video_compression = VideoCompression.find(video_compression_id)
    return unless video_compression.status == "queued"

    with_global_lock(video_compression_id) do
      video_compression.update!(status: "processing", progress_percent: 5, status_message: "Preparing FFmpeg", started_at: Time.current, error_message: nil)
      output_path = VideoCompressor.new(video_compression).call
      video_compression.update!(
        status: "succeeded",
        progress_percent: 100,
        status_message: "Ready to download",
        output_path: output_path,
        output_filename: video_compression.output_name,
        output_bytes: File.size(output_path),
        completed_at: Time.current,
        expires_at: VideoCompression::OUTPUT_TTL.from_now
      )
    rescue VideoCompressor::Error => e
      video_compression.update!(
        status: "failed",
        progress_percent: 0,
        status_message: "Failed",
        error_message: e.message.first(1_000),
        completed_at: Time.current,
        expires_at: 1.hour.from_now
      )
    ensure
      delete_input(video_compression)
    end
  end

  private

  def with_global_lock(video_compression_id)
    connection = ActiveRecord::Base.connection
    locked = connection.select_value("SELECT pg_try_advisory_lock(#{GLOBAL_LOCK_KEY})")
    unless locked
      self.class.set(wait: 30.seconds).perform_later(video_compression_id)
      return
    end

    yield
  ensure
    connection.execute("SELECT pg_advisory_unlock(#{GLOBAL_LOCK_KEY})") if locked
  end

  def delete_input(video_compression)
    FileUtils.rm_f(video_compression.input_path)
  end
end
