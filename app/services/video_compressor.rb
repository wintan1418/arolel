require "fileutils"
require "open3"
require "timeout"

class VideoCompressor
  Error = Class.new(StandardError)
  MissingDependency = Class.new(Error)
  CompressionFailed = Class.new(Error)

  TIMEOUT_SECONDS = ENV.fetch("VIDEO_COMPRESSION_TIMEOUT_SECONDS", 900).to_i
  DB_PROGRESS_INTERVAL_SECONDS = 3
  MIN_PROGRESS_STEP = 2

  def initialize(video_compression)
    @video_compression = video_compression
  end

  def call
    raise CompressionFailed, "Input video is missing." unless File.exist?(video_compression.input_path)

    FileUtils.mkdir_p(output_dir)
    output_path = File.join(output_dir, video_compression.output_basename)

    run_command(*ffmpeg_args(video_compression.input_path, output_path), duration_seconds: probe_duration_seconds(video_compression.input_path))

    raise CompressionFailed, "FFmpeg did not produce an output file." unless File.exist?(output_path)

    output_path
  end

  private

  attr_reader :video_compression

  def ffmpeg_args(input_path, output_path)
    case video_compression.operation
    when "mp4-to-mp3"
      mp4_to_mp3_args(input_path, output_path)
    when "webm-to-mp4"
      webm_to_mp4_args(input_path, output_path)
    else
      compress_video_args(input_path, output_path)
    end
  end

  def mp4_to_mp3_args(input_path, output_path)
    [
      *priority_prefix,
      ffmpeg_path,
      "-y",
      "-hide_banner",
      "-loglevel", "error",
      "-i", input_path,
      "-map", "0:a:0",
      "-vn", "-sn", "-dn",
      "-c:a", "libmp3lame",
      "-b:a", ENV.fetch("MEDIA_CONVERSION_MP3_BITRATE", "192k"),
      "-threads", ENV.fetch("VIDEO_COMPRESSION_THREADS", "1"),
      "-progress", "pipe:1",
      "-nostats",
      output_path
    ]
  end

  def webm_to_mp4_args(input_path, output_path)
    [
      *priority_prefix,
      ffmpeg_path,
      "-y",
      "-hide_banner",
      "-loglevel", "error",
      "-i", input_path,
      "-map", "0:v:0", "-map", "0:a:0?",
      "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p",
      "-c:v", "libx264",
      "-preset", ENV.fetch("VIDEO_COMPRESSION_PRESET", "veryfast"),
      "-crf", ENV.fetch("MEDIA_CONVERSION_WEBM_CRF", "28"),
      "-threads", ENV.fetch("VIDEO_COMPRESSION_THREADS", "1"),
      "-c:a", "aac", "-b:a", ENV.fetch("VIDEO_COMPRESSION_AUDIO_BITRATE", "128k"),
      "-sn", "-dn",
      "-movflags", "+faststart",
      "-progress", "pipe:1",
      "-nostats",
      output_path
    ]
  end

  def compress_video_args(input_path, output_path)
    [
      *priority_prefix,
      ffmpeg_path,
      "-y",
      "-hide_banner",
      "-loglevel", "error",
      "-i", input_path,
      "-map", "0:v:0", "-map", "0:a:0?",
      "-vf", "scale=1280:-2:force_original_aspect_ratio=decrease,format=yuv420p",
      "-c:v", "libx264",
      "-preset", ENV.fetch("VIDEO_COMPRESSION_PRESET", "veryfast"),
      "-crf", ENV.fetch("VIDEO_COMPRESSION_CRF", "32"),
      "-threads", ENV.fetch("VIDEO_COMPRESSION_THREADS", "1"),
      "-c:a", "aac", "-b:a", ENV.fetch("VIDEO_COMPRESSION_AUDIO_BITRATE", "128k"),
      "-sn", "-dn",
      "-movflags", "+faststart",
      "-progress", "pipe:1",
      "-nostats",
      output_path
    ]
  end

  def run_command(*args, duration_seconds:)
    stderr_lines = []

    Open3.popen3({ "HOME" => Dir.tmpdir }, *args) do |stdin, stdout, stderr, wait_thread|
      stdin.close

      progress_thread = Thread.new do
        stream_progress(stdout, duration_seconds)
      end

      stderr_thread = Thread.new do
        stderr.each_line do |line|
          stderr_lines << line
          stderr_lines.shift if stderr_lines.length > 25
        end
      end

      status = Timeout.timeout(TIMEOUT_SECONDS) { wait_thread.value }
      progress_thread.join(1)
      stderr_thread.join(1)

      return if status.success?
    rescue Timeout::Error
      terminate_process(wait_thread.pid)
      progress_thread.join(1)
      stderr_thread.join(1)
      raise
    end

    message = stderr_lines.last(5).join(" ").squish
    raise CompressionFailed, message.presence || "#{video_compression.operation_label} failed."
  rescue Timeout::Error
    raise CompressionFailed, "#{video_compression.operation_label} timed out. Try a smaller or shorter file."
  end

  def priority_prefix
    prefix = []
    prefix.push(nice_path, "-n", ENV.fetch("VIDEO_COMPRESSION_NICE", "15")) if nice_path
    prefix.push(ionice_path, "-c", "3") if ionice_path
    prefix
  end

  def output_dir
    File.dirname(video_compression.input_path)
  end

  def probe_duration_seconds(input_path)
    return unless ffprobe_path

    output, status = Open3.capture2e(
      { "HOME" => Dir.tmpdir },
      ffprobe_path,
      "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      input_path
    )
    return unless status.success?

    duration = output.to_f
    duration.positive? ? duration : nil
  rescue StandardError
    nil
  end

  def stream_progress(io, duration_seconds)
    last_percent = video_compression.progress_percent.to_i
    last_update_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    io.each_line do |line|
      key, value = line.strip.split("=", 2)
      next if key.blank?

      case key
      when "out_time"
        next unless duration_seconds

        seconds = ffmpeg_timestamp_to_seconds(value)
        percent = progress_percent_for(seconds, duration_seconds)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        next if percent <= last_percent
        next if (percent - last_percent) < MIN_PROGRESS_STEP && (now - last_update_at) < DB_PROGRESS_INTERVAL_SECONDS

        persist_progress(percent, active_status_message)
        last_percent = percent
        last_update_at = now
      when "progress"
        persist_progress(96, "Finalizing file") if value == "end"
      end
    end
  rescue StandardError
    nil
  end

  def ffmpeg_timestamp_to_seconds(value)
    hours, minutes, seconds = value.split(":")
    hours.to_i * 3600 + minutes.to_i * 60 + seconds.to_f
  end

  def progress_percent_for(seconds, duration_seconds)
    return 5 unless duration_seconds.to_f.positive?

    percent = 5 + ((seconds / duration_seconds) * 90).round
    percent.clamp(5, 95)
  end

  def persist_progress(percent, message)
    video_compression.update_columns(progress_percent: percent, status_message: message, updated_at: Time.current)
  end

  def active_status_message
    case video_compression.operation
    when "mp4-to-mp3"
      "Extracting audio"
    when "webm-to-mp4"
      "Transcoding video"
    else
      "Compressing video"
    end
  end

  def ffmpeg_path
    command_path(ENV["FFMPEG_PATH"].presence) ||
      command_path("ffmpeg") ||
      raise(MissingDependency, "FFmpeg is not installed on this server.")
  end

  def ffprobe_path
    command_path(ENV["FFPROBE_PATH"].presence) ||
      command_path("ffprobe")
  end

  def terminate_process(pid)
    Process.kill("TERM", pid)
    sleep 1
    Process.kill("KILL", pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def nice_path
    command_path("nice")
  end

  def ionice_path
    command_path("ionice")
  end

  def command_path(command)
    return if command.blank?
    return command if command.include?(File::SEPARATOR) && File.executable?(command)

    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |path| File.join(path, command) }.find { |path| File.executable?(path) }
  end
end
